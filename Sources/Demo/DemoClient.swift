import Foundation

/// Made-up catalogue for the demo mode: no network, no real titles, no personal data.
struct DemoClient: IPTVClient {
    func authenticate() async throws {}

    func categories(for kind: MediaKind) async throws -> [ContentCategory] {
        DemoCatalog.categories[kind] ?? []
    }

    func items(kind: MediaKind, categoryId: String?) async throws -> [MediaItem] {
        let all = DemoCatalog.items(kind)
        guard let categoryId else { return all }
        return all.filter { $0.categoryId == categoryId }
    }

    func seriesDetail(for item: MediaItem) async throws -> SeriesDetail {
        DemoCatalog.seriesDetail(item)
    }

    func streamURL(kind: MediaKind, playbackRef: String, containerExtension: String?) async throws -> URL {
        throw IPTVError.unsupported("Playback in demo mode")
    }

    func shortEPG(forChannelRef ref: String) async throws -> [EPGEntry] {
        DemoCatalog.epg(channel: ref)
    }
}

enum DemoCatalog {
    static let categories: [MediaKind: [ContentCategory]] = [
        .live: [ContentCategory(id: "news", name: "News"), ContentCategory(id: "sport", name: "Sport"),
                ContentCategory(id: "ent", name: "Entertainment")],
        .movie: [ContentCategory(id: "drama", name: "Drama"), ContentCategory(id: "thriller", name: "Thrillers"),
                 ContentCategory(id: "comedy", name: "Comedy"), ContentCategory(id: "docs", name: "Documentaries")],
        .series: [ContentCategory(id: "s-drama", name: "Drama Series"),
                  ContentCategory(id: "s-crime", name: "Crime Series")],
    ]

    private static let channels: [(String, String)] = [
        ("News 24", "news"), ("Sport One", "sport"), ("Cinema+", "ent"), ("Kids Zone", "ent"),
        ("Docu World", "ent"), ("Music Hits", "ent"), ("Weather Live", "news"), ("Nature HD", "ent"),
        ("Arena Sport 2", "sport"), ("Horizons TV", "ent"),
    ]

    private static let movies: [(String, String, String, Double)] = [
        ("The Long Horizon", "drama", "2025", 4.3), ("Midnight Harbor", "thriller", "2024", 4.1),
        ("Echoes of Glass", "drama", "2023", 3.9), ("Paper Satellites", "comedy", "2025", 3.7),
        ("Northbound", "thriller", "2022", 4.0), ("The Quiet Engine", "docs", "2024", 4.4),
        ("Saltwater Kings", "drama", "2021", 3.8), ("Lantern Season", "comedy", "2023", 3.6),
        ("Cold Light Avenue", "thriller", "2025", 4.2), ("After the Tide", "drama", "2024", 4.0),
        ("Signal Lost", "thriller", "2023", 3.9), ("Golden Hour Club", "comedy", "2022", 3.5),
        ("Deep Field", "docs", "2025", 4.5), ("The Glass Orchard", "drama", "2022", 3.8),
    ]

    private static let series: [(String, String, String, Double)] = [
        ("Harbor Lights", "s-drama", "2023", 4.4), ("The Cartographers", "s-drama", "2024", 4.2),
        ("Night Shift Diaries", "s-crime", "2022", 4.0), ("Copper & Rust", "s-crime", "2025", 4.3),
        ("Blue Meridian", "s-drama", "2021", 3.9), ("Wildwood", "s-drama", "2024", 4.1),
        ("The Archive", "s-crime", "2023", 4.2), ("Second Orbit", "s-drama", "2025", 4.0),
    ]

    private static let plots = [
        "A quiet coastal town is shaken when an old lighthouse starts signalling again.",
        "Two strangers race across a frozen country to deliver a message that could change everything.",
        "An archivist finds a film reel that should not exist, and someone wants it back.",
        "A small crew of misfits takes on one last job before the harbour closes for good.",
        "Mapmakers sent to chart an island discover it is not on any map for a reason.",
        "A night-shift nurse starts noticing the same patient in every ward.",
    ]

    static func items(_ kind: MediaKind) -> [MediaItem] {
        switch kind {
        case .live:
            return channels.enumerated().map { index, channel in
                MediaItem(id: "demo-live-\(index)", kind: .live, name: channel.0, categoryId: channel.1,
                          playbackRef: "\(index)")
            }
        case .movie, .series:
            let source = kind == .movie ? movies : series
            return source.enumerated().map { index, title in
                MediaItem(id: "demo-\(kind.rawValue)-\(index)", kind: kind, name: title.0, categoryId: title.1,
                          playbackRef: "\(index)", rating: title.3, plot: plots[index % plots.count], year: title.2)
            }
        }
    }

    private static let episodeTitles = [
        "Pilot", "Low Tide", "The Keeper", "Static", "Northern Lights", "Undertow", "Signal Fires", "Homecoming",
    ]

    static func seriesDetail(_ item: MediaItem) -> SeriesDetail {
        let seasonCount = item.name == "Harbor Lights" ? 3 : 2
        var seasons: [Int: [Episode]] = [:]
        for season in 1...seasonCount {
            seasons[season] = episodeTitles.enumerated().map { index, title in
                Episode(
                    id: "\(item.id)-s\(season)e\(index + 1)",
                    title: title,
                    season: season,
                    episode: index + 1,
                    plot: plots[(index + season) % plots.count],
                    posterURL: nil,
                    playbackRef: "\(season)-\(index + 1)",
                    containerExtension: "mp4"
                )
            }
        }
        return SeriesDetail(item: item, seasons: seasons)
    }

    static func epg(channel: String) -> [EPGEntry] {
        let shows = ["Morning Edition", "World Today", "The Debate", "Midday Report", "Business Hour",
                     "Evening News"]
        let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        return shows.enumerated().map { index, title in
            EPGEntry(
                id: "\(channel)-\(index)",
                title: title,
                start: start.addingTimeInterval(Double(index) * 3600),
                end: start.addingTimeInterval(Double(index + 1) * 3600),
                description: "Live coverage and analysis of the day's main stories."
            )
        }
    }
}
