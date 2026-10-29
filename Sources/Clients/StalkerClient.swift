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
        req.setValue(Self.stbUserAgent, forHTTPHeaderField: "User-Agent")
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
                    // Loading everything at once passes no category: take the item's own.
                    categoryId: vod["category_id"].map { "\($0)" } ?? categoryId,
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
        // Ministra: `movie_id=<series id>&season_id=0` lists the seasons, `season_id=<season id>` its episodes.
        // Portals that don't support it ignore `movie_id` and return the whole catalog: those entries are
        // filtered out by id and the series is then exposed as a single playable item.
        try await ensureToken()
        let seriesId = Self.rawId(of: item)
        let seriesBase = seriesId.components(separatedBy: ":").first ?? seriesId
        let seasonEntries = await orderedList(movieId: seriesId, seasonId: "0").filter { entry in
            guard let id = entry["id"].map({ "\($0)" }), id != seriesId else { return false }
            return Self.flag(entry["is_season"]) || id.hasPrefix("\(seriesBase):")
        }

        var seasons: [Int: [Episode]] = [:]
        for (index, entry) in seasonEntries.enumerated() {
            guard let seasonId = entry["id"].map({ "\($0)" }) else { continue }
            let season = Self.seasonNumber(of: entry, id: seasonId) ?? index + 1
            seasons[season] = await episodes(of: entry, seasonId: seasonId, season: season, series: item)
                .sorted { $0.episode < $1.episode }
        }
        return SeriesDetail(item: item, seasons: seasons.filter { !$0.value.isEmpty })
    }

    /// Episodes of a season: either listed inline (`series: [1, 2, …]`, played through the season's cmd)
    /// or fetched as their own entries, each with its own cmd.
    private func episodes(of seasonEntry: [String: Any], seasonId: String, season: Int,
                          series item: MediaItem) async -> [Episode] {
        let poster = (seasonEntry["screenshot_uri"] as? String).flatMap { self.absoluteURL($0) }
        let inline = ((seasonEntry["series"] as? [Any]) ?? []).compactMap { Int("\($0)") }
        if !inline.isEmpty, let cmd = seasonEntry["cmd"] as? String, !cmd.isEmpty {
            return inline.map { number in
                Episode(id: "\(seasonId)-\(number)", title: "Episode \(number)", season: season, episode: number,
                        plot: seasonEntry["description"] as? String, posterURL: poster,
                        playbackRef: "\(cmd)|episode=\(number)", containerExtension: nil)
            }
        }

        let entries = await orderedList(movieId: Self.rawId(of: item), seasonId: seasonId)
        return entries.enumerated().compactMap { index, entry in
            guard let id = entry["id"].map({ "\($0)" }), id != seasonId,
                  let cmd = entry["cmd"] as? String, !cmd.isEmpty else { return nil }
            let name = entry["name"] as? String
            let number = (entry["series_number"]).flatMap { Int("\($0)") }
                ?? name.flatMap(Self.episodeNumber(inName:)) ?? index + 1
            return Episode(
                id: id,
                title: name ?? "Episode \(number)",
                season: season,
                episode: number,
                plot: entry["description"] as? String,
                posterURL: (entry["screenshot_uri"] as? String).flatMap { self.absoluteURL($0) } ?? poster,
                playbackRef: cmd,
                containerExtension: nil
            )
        }
    }

    /// `get_ordered_list` for a series level, following pagination (portals return ~14 per page).
    private func orderedList(movieId: String, seasonId: String) async -> [[String: Any]] {
        var entries: [[String: Any]] = []
        var page = 1
        var totalPages = 1
        while page <= min(totalPages, 20) {
            let extra = [URLQueryItem(name: "movie_id", value: movieId),
                         URLQueryItem(name: "season_id", value: seasonId),
                         URLQueryItem(name: "episode_id", value: "0"),
                         URLQueryItem(name: "p", value: String(page))]
            guard let dict = try? await fetchJS(type: "series", action: "get_ordered_list", extra: extra)
                    as? [String: Any],
                  let data = dict["data"] as? [[String: Any]], !data.isEmpty else { break }
            if page == 1 {
                let total = Int("\(dict["total_items"] ?? "")") ?? data.count
                totalPages = max(1, Int(ceil(Double(total) / Double(data.count))))
            }
            entries.append(contentsOf: data)
            page += 1
        }
        return entries
    }

    /// The portal's own id of an item (`MediaItem.id` is `<provider>-<kind>-<id>`).
    private static func rawId(of item: MediaItem) -> String {
        let prefix = "\(item.kind.rawValue)-"
        guard let range = item.id.range(of: prefix, options: .backwards) else { return item.playbackRef }
        return String(item.id[range.upperBound...])
    }

    /// Portals send booleans as true, 1 or "1".
    private static func flag(_ value: Any?) -> Bool {
        guard let value else { return false }
        return (value as? Bool) ?? ["1", "true"].contains("\(value)".lowercased())
    }

    /// Season number from `season_number`, the name ("Season 2", "Saison 2", "S02") or the `<series>:<season>` id.
    private static func seasonNumber(of entry: [String: Any], id: String) -> Int? {
        if let value = entry["season_number"], let number = Int("\(value)") { return number }
        if let name = entry["name"] as? String, let number = seasonNumber(inName: name) { return number }
        return id.split(separator: ":").last.flatMap { Int($0) }
    }

    /// Number following an episode keyword ("Episode 3", "Épisode 03", "S01E03", "E03").
    private static func episodeNumber(inName name: String) -> Int? {
        let pattern = /(?i)(?:épisode|episode|\bs\d{1,3}\s*e|\be)\s*0*(\d{1,4})(?!\d)/
        return name.firstMatch(of: pattern).flatMap { Int($0.1) }
    }

    /// Number following a season keyword ("Season 2", "Saison 02", "S2"), else a name that is only a number.
    private static func seasonNumber(inName name: String) -> Int? {
        let pattern = /(?i)(?:season|saison|staffel|temporada|stagione|\bs)\s*0*(\d{1,3})(?!\d)/
        if let match = name.firstMatch(of: pattern) { return Int(match.1) }
        return Int(name.trimmingCharacters(in: .whitespaces))
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
        return Self.playableURL(from: url, portalBase: provider.baseURL)
    }

    func shortEPG(forChannelRef ref: String) async throws -> [EPGEntry] {
        // Short EPG by channel cmd is not consistently available on Stalker portals.
        return []
    }

    var streamHeaders: [String: String] {
        ["User-Agent": Self.stbUserAgent]
    }

    // MARK: - Helpers

    private static let stbUserAgent =
        "Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3"

    /// Some portals return `localhost` in create_link results; replace it with the portal host.
    /// Raw MPEG-TS links are left as-is: the VLC engine plays them directly.
    static func playableURL(from url: URL, portalBase: URL?) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased(),
              host == "localhost" || host == "127.0.0.1",
              let portalHost = portalBase?.host else { return url }
        components.host = portalHost
        if components.port == nil { components.port = portalBase?.port }
        return components.url ?? url
    }

    private func absoluteURL(_ string: String) -> URL? {
        if string.hasPrefix("http") { return URL(string: string) }
        guard let base = provider.baseURL else { return nil }
        return URL(string: string, relativeTo: base)?.absoluteURL
    }
}

// MARK: - Account

extension StalkerClient {
    /// Portals put the end date in `account_info/get_main_info` or in the profile, under various names.
    func accountInfo() async throws -> AccountInfo {
        try await ensureToken()
        let keys = ["end_date", "expire_billing_date", "tariff_expired_date", "expire_date", "exp_date"]
        for (type, action) in [("account_info", "get_main_info"), ("stb", "get_profile")] {
            guard let dict = try? await fetchJS(type: type, action: action) as? [String: Any] else { continue }
            for key in keys {
                guard let value = dict[key] else { continue }
                if "\(value)".lowercased().contains("unlimited") { return AccountInfo(isUnlimited: true) }
                if let date = AccountInfo.date(from: value) { return AccountInfo(expiresAt: date) }
            }
        }
        return AccountInfo()
    }
}
