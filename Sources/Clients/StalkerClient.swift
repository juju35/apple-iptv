import Foundation

/// Stalker / Ministra middleware client (portal.php, MAC-address authentication).
final class StalkerClient: IPTVClient {
    let provider: Provider

    private var token: String?

    init(provider: Provider) {
        self.provider = provider
    }

    // MARK: - Requests

    private var portalURL: URL? {
        guard let base = provider.baseURL else { return nil }
        // Accept both `http://host` and `http://host/stalker_portal` style URLs.
        if base.path.contains("portal.php") || base.path.contains("load.php") {
            return base
        }
        if base.path.contains("stalker_portal") {
            return base.appendingPathComponent("server/load.php")
        }
        return base.appendingPathComponent("portal.php")
    }

    private func request(type: String, action: String, extra: [URLQueryItem] = []) throws -> URLRequest {
        guard let portal = portalURL,
              var components = URLComponents(url: portal, resolvingAgainstBaseURL: false) else {
            throw IPTVError.invalidURL
        }
        var items = [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "action", value: action),
            URLQueryItem(name: "JsHttpRequest", value: "1-xml")
        ]
        items.append(contentsOf: extra)
        components.queryItems = items
        guard let url = components.url else { throw IPTVError.invalidURL }

        var req = URLRequest(url: url)
        let mac = provider.macAddress.uppercased()
        let cookie = "mac=\(mac); stb_lang=en; timezone=Europe/Paris"
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        req.setValue("Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("Model: MAG250; Link: WiFi", forHTTPHeaderField: "X-User-Agent")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func fetchJS(type: String, action: String, extra: [URLQueryItem] = []) async throws -> Any {
        let req = try request(type: type, action: action, extra: extra)
        let (data, response) = try await URLSession.iptv.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw IPTVError.badResponse(http.statusCode)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let js = root["js"] else {
            throw IPTVError.decoding("\(type)/\(action)")
        }
        return js
    }

    // MARK: - IPTVClient

    func authenticate() async throws {
        let js = try await fetchJS(type: "stb", action: "handshake",
                                   extra: [URLQueryItem(name: "token", value: "")])
        guard let dict = js as? [String: Any], let token = dict["token"] as? String, !token.isEmpty else {
            throw IPTVError.authenticationFailed("handshake rejected (check MAC address)")
        }
        self.token = token
        // get_profile completes the login; some portals require it before any content call.
        _ = try? await fetchJS(type: "stb", action: "get_profile")
    }

    private func ensureToken() async throws {
        if token == nil { try await authenticate() }
    }

    func categories(for kind: MediaKind) async throws -> [ContentCategory] {
        try await ensureToken()
        let (type, action): (String, String)
        switch kind {
        case .live: (type, action) = ("itv", "get_genres")
        case .movie: (type, action) = ("vod", "get_categories")
        case .series: (type, action) = ("series", "get_categories")
        }
        guard let array = try await fetchJS(type: type, action: action) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { dict in
            guard let id = dict["id"].map({ "\($0)" }),
                  let name = dict["title"] as? String else { return nil }
            return ContentCategory(id: id, name: name)
        }
    }

    func items(kind: MediaKind, categoryId: String?) async throws -> [MediaItem] {
        try await ensureToken()
        switch kind {
        case .live:
            return try await liveChannels(categoryId: categoryId)
        case .movie, .series:
            return try await vodItems(kind: kind, categoryId: categoryId)
        }
    }

    private func liveChannels(categoryId: String?) async throws -> [MediaItem] {
        let js = try await fetchJS(type: "itv", action: "get_all_channels")
        guard let dict = js as? [String: Any],
              let data = dict["data"] as? [[String: Any]] else {
            throw IPTVError.decoding("get_all_channels")
        }
        return data.compactMap { ch in
            guard let id = ch["id"].map({ "\($0)" }),
                  let name = ch["name"] as? String,
                  let cmd = ch["cmd"] as? String else { return nil }
            let genreId = ch["tv_genre_id"].map { "\($0)" }
            if let categoryId, genreId != categoryId { return nil }
            let logo = (ch["logo"] as? String).flatMap { self.absoluteURL($0) }
            return MediaItem(
                id: "\(provider.id)-live-\(id)",
                kind: .live,
                name: name,
                posterURL: logo,
                categoryId: genreId,
                playbackRef: cmd
            )
        }
    }

    private func vodItems(kind: MediaKind, categoryId: String?) async throws -> [MediaItem] {
        let type = kind == .movie ? "vod" : "series"
        var items: [MediaItem] = []
        var page = 1
        var totalPages = 1
        while page <= min(totalPages, 20) {
            var extra = [URLQueryItem(name: "p", value: String(page)),
                         URLQueryItem(name: "sortby", value: "added")]
            if let categoryId { extra.append(URLQueryItem(name: "category", value: categoryId)) }
            let js = try await fetchJS(type: type, action: "get_ordered_list", extra: extra)
            guard let dict = js as? [String: Any],
                  let data = dict["data"] as? [[String: Any]] else { break }
            if page == 1 {
                let total = (dict["total_items"] as? Int)
                    ?? Int("\(dict["total_items"] ?? "0")") ?? data.count
                let perPage = max(data.count, 1)
                totalPages = max(1, Int(ceil(Double(total) / Double(perPage))))
            }
            items.append(contentsOf: data.compactMap { vod in
                guard let id = vod["id"].map({ "\($0)" }),
                      let name = vod["name"] as? String else { return nil }
                let cmd = vod["cmd"] as? String ?? "/media/\(id).mpg"
                return MediaItem(
                    id: "\(provider.id)-\(kind.rawValue)-\(id)",
                    kind: kind,
                    name: name,
                    posterURL: (vod["screenshot_uri"] as? String).flatMap { self.absoluteURL($0) },
                    categoryId: categoryId,
                    playbackRef: cmd,
                    rating: Double("\(vod["rating_imdb"] ?? "")"),
                    plot: vod["description"] as? String,
                    year: vod["year"].map { "\($0)" }
                )
            })
            page += 1
        }
        return items
    }

    func seriesDetail(for item: MediaItem) async throws -> SeriesDetail {
        // Stalker portals vary a lot here; expose the series itself as a single playable item
        // and list seasons when the portal provides them via get_ordered_list with movie_id.
        try await ensureToken()
        let js = try? await fetchJS(type: "series", action: "get_ordered_list",
                                    extra: [URLQueryItem(name: "movie_id", value: item.playbackRef)])
        guard let dict = js as? [String: Any],
              let data = dict["data"] as? [[String: Any]], !data.isEmpty else {
            return SeriesDetail(item: item, seasons: [:])
        }
        var seasons: [Int: [Episode]] = [:]
        for entry in data {
            guard let id = entry["id"].map({ "\($0)" }) else { continue }
            let season = Int("\(entry["season_number"] ?? "1")") ?? 1
            let episodes = (entry["series"] as? [Int]) ?? []
            let cmd = entry["cmd"] as? String ?? ""
            let eps = episodes.isEmpty ? [0] : episodes
            for ep in eps {
                let episode = Episode(
                    id: "\(id)-\(ep)",
                    title: entry["name"] as? String ?? item.name,
                    season: season,
                    episode: ep,
                    plot: entry["description"] as? String,
                    posterURL: (entry["screenshot_uri"] as? String).flatMap { self.absoluteURL($0) },
                    playbackRef: ep == 0 ? cmd : "\(cmd)|episode=\(ep)",
                    containerExtension: nil
                )
                seasons[season, default: []].append(episode)
            }
        }
        return SeriesDetail(item: item, seasons: seasons)
    }

    func streamURL(kind: MediaKind, playbackRef: String, containerExtension: String?) async throws -> URL {
        try await ensureToken()
        let (type, extraEpisode): (String, String?) = {
            switch kind {
            case .live: return ("itv", nil)
            case .movie: return ("vod", nil)
            case .series:
                if let range = playbackRef.range(of: "|episode=") {
                    return ("vod", String(playbackRef[range.upperBound...]))
                }
                return ("vod", nil)
            }
        }()
        let cmd = playbackRef.components(separatedBy: "|episode=").first ?? playbackRef

        var extra = [URLQueryItem(name: "cmd", value: cmd)]
        if let extraEpisode {
            extra.append(URLQueryItem(name: "series", value: extraEpisode))
        }
        let js = try await fetchJS(type: type, action: "create_link", extra: extra)
        guard let dict = js as? [String: Any], let rawCmd = dict["cmd"] as? String else {
            throw IPTVError.decoding("create_link")
        }
        // cmd is typically "ffmpeg http://..." or "auto http://..."
        guard let urlString = rawCmd
            .components(separatedBy: " ")
            .first(where: { $0.hasPrefix("http") }),
              let url = URL(string: urlString) else {
            throw IPTVError.decoding("create_link cmd: \(rawCmd)")
        }
        return url
    }

    func shortEPG(forChannelRef ref: String) async throws -> [EPGEntry] {
        // Short EPG by channel cmd is not consistently available on Stalker portals.
        return []
    }

    // MARK: - Helpers

    private func absoluteURL(_ string: String) -> URL? {
        if string.hasPrefix("http") { return URL(string: string) }
        guard let base = provider.baseURL else { return nil }
        return URL(string: string, relativeTo: base)?.absoluteURL
    }
}
