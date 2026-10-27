import Foundation

/// Xtream Codes client (player_api.php).
final class XtreamClient: IPTVClient {
    let provider: Provider

    init(provider: Provider) {
        self.provider = provider
    }

    // MARK: - Requests

    private func apiURL(action: String?, extra: [URLQueryItem] = []) throws -> URL {
        guard let base = provider.baseURL,
              var components = URLComponents(url: base.appendingPathComponent("player_api.php"),
                                             resolvingAgainstBaseURL: false) else {
            throw IPTVError.invalidURL
        }
        var items = [
            URLQueryItem(name: "username", value: provider.username),
            URLQueryItem(name: "password", value: provider.password)
        ]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        items.append(contentsOf: extra)
        components.queryItems = items
        guard let url = components.url else { throw IPTVError.invalidURL }
        return url
    }

    private func fetchJSON(action: String?, extra: [URLQueryItem] = []) async throws -> Any {
        let url = try apiURL(action: action, extra: extra)
        let (data, response) = try await URLSession.iptv.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw IPTVError.badResponse(http.statusCode)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: - IPTVClient

    func authenticate() async throws {
        let json = try await fetchJSON(action: nil)
        guard let dict = json as? [String: Any],
              let userInfo = dict["user_info"] as? [String: Any] else {
            throw IPTVError.decoding("user_info")
        }
        let auth = (userInfo["auth"] as? Int) ?? Int("\(userInfo["auth"] ?? "")") ?? 0
        guard auth == 1 else {
            let status = userInfo["status"] as? String ?? "unknown"
            throw IPTVError.authenticationFailed(status)
        }
    }

    func categories(for kind: MediaKind) async throws -> [ContentCategory] {
        let action: String
        switch kind {
        case .live: action = "get_live_categories"
        case .movie: action = "get_vod_categories"
        case .series: action = "get_series_categories"
        }
        guard let array = try await fetchJSON(action: action) as? [[String: Any]] else {
            throw IPTVError.decoding(action)
        }
        return array.compactMap { dict in
            guard let id = Self.string(dict["category_id"]),
                  let name = dict["category_name"] as? String else { return nil }
            return ContentCategory(id: id, name: name)
        }
    }

    func items(kind: MediaKind, categoryId: String?) async throws -> [MediaItem] {
        let action: String
        switch kind {
        case .live: action = "get_live_streams"
        case .movie: action = "get_vod_streams"
        case .series: action = "get_series"
        }
        var extra: [URLQueryItem] = []
        if let categoryId { extra.append(URLQueryItem(name: "category_id", value: categoryId)) }
        guard let array = try await fetchJSON(action: action, extra: extra) as? [[String: Any]] else {
            throw IPTVError.decoding(action)
        }
        return array.compactMap { dict in
            let idKey = kind == .series ? "series_id" : "stream_id"
            guard let rawId = Self.string(dict[idKey]),
                  let name = dict["name"] as? String else { return nil }
            let posterKey = kind == .series ? "cover" : "stream_icon"
            let poster = (dict[posterKey] as? String).flatMap(URL.init(string:))
            return MediaItem(
                id: "\(provider.id)-\(kind.rawValue)-\(rawId)",
                kind: kind,
                name: name,
                posterURL: poster,
                categoryId: Self.string(dict["category_id"]),
                playbackRef: rawId,
                containerExtension: dict["container_extension"] as? String,
                rating: Self.double(dict["rating"] ?? dict["rating_5based"]),
                plot: dict["plot"] as? String,
                year: Self.string(dict["year"] ?? dict["releaseDate"])
            )
        }
    }

    func seriesDetail(for item: MediaItem) async throws -> SeriesDetail {
        let json = try await fetchJSON(action: "get_series_info",
                                       extra: [URLQueryItem(name: "series_id", value: item.playbackRef)])
        guard let dict = json as? [String: Any],
              let episodesDict = dict["episodes"] as? [String: [[String: Any]]] else {
            return SeriesDetail(item: item, seasons: [:])
        }
        var seasons: [Int: [Episode]] = [:]
        for (seasonKey, list) in episodesDict {
            let season = Int(seasonKey) ?? 0
            seasons[season] = list.compactMap { ep in
                guard let id = Self.string(ep["id"]) else { return nil }
                let info = ep["info"] as? [String: Any]
                return Episode(
                    id: id,
                    title: ep["title"] as? String ?? "Episode",
                    season: season,
                    episode: Self.int(ep["episode_num"]) ?? 0,
                    plot: info?["plot"] as? String,
                    posterURL: (info?["movie_image"] as? String).flatMap(URL.init(string:)),
                    playbackRef: id,
                    containerExtension: ep["container_extension"] as? String
                )
            }.sorted { $0.episode < $1.episode }
        }
        return SeriesDetail(item: item, seasons: seasons)
    }

    func streamURL(kind: MediaKind, playbackRef: String, containerExtension: String?) async throws -> URL {
        guard let base = provider.baseURL else { throw IPTVError.invalidURL }
        let user = provider.username
        let pass = provider.password
        let path: String
        switch kind {
        case .live:
            path = "live/\(user)/\(pass)/\(playbackRef).m3u8"
        case .movie:
            path = "movie/\(user)/\(pass)/\(playbackRef).\(containerExtension ?? "mp4")"
        case .series:
            path = "series/\(user)/\(pass)/\(playbackRef).\(containerExtension ?? "mp4")"
        }
        return base.appendingPathComponent(path)
    }

    func shortEPG(forChannelRef ref: String) async throws -> [EPGEntry] {
        let json = try await fetchJSON(action: "get_short_epg",
                                       extra: [URLQueryItem(name: "stream_id", value: ref)])
        guard let dict = json as? [String: Any],
              let listings = dict["epg_listings"] as? [[String: Any]] else { return [] }
        return listings.compactMap { entry in
            guard let id = Self.string(entry["id"]),
                  let startTs = Self.double(entry["start_timestamp"]),
                  let endTs = Self.double(entry["stop_timestamp"]) else { return nil }
            return EPGEntry(
                id: id,
                title: Self.base64Decoded(entry["title"] as? String) ?? "—",
                start: Date(timeIntervalSince1970: startTs),
                end: Date(timeIntervalSince1970: endTs),
                description: Self.base64Decoded(entry["description"] as? String)
            )
        }
    }

    // MARK: - Helpers

    private static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let i = value as? Int { return String(i) }
        if let d = value as? Double { return String(Int(d)) }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func base64Decoded(_ string: String?) -> String? {
        guard let string else { return nil }
        if let data = Data(base64Encoded: string), let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        return string
    }
}
