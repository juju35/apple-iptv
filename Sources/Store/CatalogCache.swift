import Foundation

/// Categories and items of a provider, as returned by its client.
struct Catalog: Codable {
    var liveCategories: [ContentCategory] = []
    var movieCategories: [ContentCategory] = []
    var seriesCategories: [ContentCategory] = []
    var liveItems: [MediaItem] = []
    var movieItems: [MediaItem] = []
    var seriesItems: [MediaItem] = []

    var isEmpty: Bool { liveItems.isEmpty && movieItems.isEmpty && seriesItems.isEmpty }
}

/// On-disk copy of each provider's catalog (one JSON file per provider in Caches), so the app
/// shows its lists right away instead of waiting for the portal. The system may purge it.
enum CatalogCache {
    struct Entry: Codable {
        let savedAt: Date
        let catalog: Catalog
    }

    /// Lifetimes offered in Settings, in seconds; 0 turns the cache off.
    static let lifetimes: [(label: String, seconds: TimeInterval)] = [
        ("Off", 0),
        ("1 hour", 3600),
        ("6 hours", 6 * 3600),
        ("12 hours", 12 * 3600),
        ("1 day", 24 * 3600),
        ("3 days", 3 * 24 * 3600),
        ("1 week", 7 * 24 * 3600),
    ]
    static let defaultLifetime: TimeInterval = 12 * 3600

    static func load(providerID: UUID) async -> Entry? {
        let url = fileURL(providerID)
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(Entry.self, from: data)
        }.value
    }

    static func save(_ catalog: Catalog, providerID: UUID) {
        let url = fileURL(providerID)
        let entry = Entry(savedAt: Date(), catalog: catalog)
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(entry) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            // Catalogs saved in previous formats.
            for old in ["Catalogs", "Catalogs-v2", "Catalogs-v3"] {
                try? FileManager.default.removeItem(at: URL.cachesDirectory.appending(path: old))
            }
        }
    }

    static func remove(providerID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(providerID))
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Bumped when cached catalogs become unusable (v2: Stalker movies and series got their categories,
    /// v3: Xtream items their `category_ids`, v4: Xtream channels their `epg_channel_id`).
    private static var directory: URL {
        URL.cachesDirectory.appending(path: "Catalogs-v4", directoryHint: .isDirectory)
    }

    private static func fileURL(_ providerID: UUID) -> URL {
        directory.appending(path: "\(providerID.uuidString).json")
    }
}
