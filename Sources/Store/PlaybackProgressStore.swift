import Foundation

/// How far a movie or an episode was watched; synced across devices through iCloud.
struct PlaybackProgress: Codable, Hashable {
    /// `MediaItem.id` for a movie, `<series item id>#<episode id>` for an episode.
    let key: String
    /// The movie or series listed under Continue Watching.
    let itemId: String
    var episodeId: String?
    var season: Int?
    var episode: Int?
    /// Seconds.
    var position: Double
    var duration: Double
    var updatedAt: Date
    /// Watched to the end: kept for a while so other devices drop it too, never resumed.
    var isFinished: Bool
    /// Removed from Continue Watching by the user: kept (and synced) so other devices drop it too, never resumed.
    /// Optional for entries saved before it existed.
    var isDismissed: Bool?
    /// The movie or series as it was played, to list it under Continue Watching even when the loaded
    /// lists don't hold it (Stalker portals page their catalogue). Optional for older entries.
    var item: MediaItem?

    /// Offered to resume and listed under Continue Watching.
    var isResumable: Bool { !isFinished && isDismissed != true }

    var fraction: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }

    /// "S1 E3" for an episode.
    var episodeLabel: String? {
        guard let season, let episode else { return nil }
        return "S\(season) E\(episode)"
    }
}

extension PlaybackProgress {
    /// Union of both sides, the most recent entry winning for each key.
    static func merged(_ entries: [PlaybackProgress],
                       into current: [String: PlaybackProgress]) -> [String: PlaybackProgress] {
        var result = current
        for entry in entries where (result[entry.key]?.updatedAt ?? .distantPast) < entry.updatedAt {
            result[entry.key] = entry
        }
        return pruned(result)
    }

    /// Keeps the store well under the iCloud key-value quota: per provider, finished entries (the
    /// "watched" checkmarks) for 180 days, and the 300 most recent overall.
    static func pruned(_ entries: [String: PlaybackProgress]) -> [String: PlaybackProgress] {
        let cutoff = Date().addingTimeInterval(-180 * 24 * 3600)
        let kept = Dictionary(grouping: entries.values, by: \.providerKey).values.flatMap { group in
            group.filter { !$0.isFinished || $0.updatedAt > cutoff }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(300)
        }
        return Dictionary(kept.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The provider the entry belongs to: item ids start with their provider's id (a UUID).
    var providerKey: String { String(itemId.prefix(36)) }
}

/// A movie or series being watched, with its most recent progress.
struct ContinueWatchingEntry: Identifiable {
    let item: MediaItem
    let progress: PlaybackProgress
    var id: String { item.id }
}

/// Identifies what a playback request should save its progress under (nil for live TV).
struct PlaybackProgressContext {
    let key: String
    let itemId: String
    var item: MediaItem?
    var episodeId: String?
    var season: Int?
    var episode: Int?

    static func movie(_ item: MediaItem) -> Self {
        Self(key: item.id, itemId: item.id, item: item)
    }

    static func episode(_ episode: Episode, of series: MediaItem) -> Self {
        Self(key: "\(series.id)#\(episode.id)", itemId: series.id, item: series, episodeId: episode.id,
             season: episode.season, episode: episode.episode)
    }
}

/// Persists playback progress in iCloud Key-Value Store (UserDefaults as fallback), one key per
/// provider (`iptv.playbackProgress.<provider id>`), like `ProviderSyncStore` does for providers.
final class PlaybackProgressSyncStore {
    /// Before progress was kept per provider: read once, then split.
    static let legacyKey = "iptv.playbackProgress"
    private static let prefix = "iptv.playbackProgress."

    private let kvs = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard

    /// Called on the main queue with the other device's entries when they change.
    var onExternalChange: (([PlaybackProgress]) -> Void)?

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            guard changedKeys?.contains(where: { $0.hasPrefix(Self.legacyKey) }) ?? true else { return }
            self.onExternalChange?(self.load())
        }
        kvs.synchronize()
        migrate()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Every provider's entries.
    func load() -> [PlaybackProgress] {
        let keys = Set(kvs.dictionaryRepresentation.keys).union(defaults.dictionaryRepresentation().keys)
            .filter { $0.hasPrefix(Self.prefix) }
        return keys.flatMap { decode(kvs.data(forKey: $0) ?? defaults.data(forKey: $0)) }
    }

    /// Writes each provider's entries under its own key.
    func save(_ entries: [PlaybackProgress]) {
        for (provider, group) in Dictionary(grouping: entries, by: \.providerKey) {
            guard let data = try? JSONEncoder().encode(group) else { continue }
            kvs.set(data, forKey: Self.prefix + provider)
            defaults.set(data, forKey: Self.prefix + provider)
        }
    }

    /// Splits the single list older versions kept into per-provider keys.
    private func migrate() {
        let legacy = decode(kvs.data(forKey: Self.legacyKey) ?? defaults.data(forKey: Self.legacyKey))
        guard !legacy.isEmpty else { return }
        let merged = PlaybackProgress.merged(legacy, into: Dictionary(load().map { ($0.key, $0) },
                                                                        uniquingKeysWith: { first, _ in first }))
        save(Array(merged.values))
        kvs.removeObject(forKey: Self.legacyKey)
        defaults.removeObject(forKey: Self.legacyKey)
    }

    private func decode(_ data: Data?) -> [PlaybackProgress] {
        guard let data, let entries = try? JSONDecoder().decode([PlaybackProgress].self, from: data) else { return [] }
        return entries
    }
}
