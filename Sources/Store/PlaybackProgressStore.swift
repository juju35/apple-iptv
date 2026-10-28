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

    /// Keeps the store well under the iCloud key-value quota: finished entries (the "watched"
    /// checkmarks) for 180 days, and the 300 most recent overall.
    static func pruned(_ entries: [String: PlaybackProgress]) -> [String: PlaybackProgress] {
        let cutoff = Date().addingTimeInterval(-180 * 24 * 3600)
        let kept = entries.values
            .filter { !$0.isFinished || $0.updatedAt > cutoff }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(300)
        return Dictionary(kept.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }
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
    var episodeId: String?
    var season: Int?
    var episode: Int?

    static func movie(_ item: MediaItem) -> Self {
        Self(key: item.id, itemId: item.id)
    }

    static func episode(_ episode: Episode, of series: MediaItem) -> Self {
        Self(key: "\(series.id)#\(episode.id)", itemId: series.id, episodeId: episode.id,
             season: episode.season, episode: episode.episode)
    }
}

/// Persists playback progress in iCloud Key-Value Store (UserDefaults as fallback),
/// like `ProviderSyncStore` does for providers.
final class PlaybackProgressSyncStore {
    static let progressKey = "iptv.playbackProgress"

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
            guard changedKeys?.contains(Self.progressKey) ?? true else { return }
            self.onExternalChange?(self.load())
        }
        kvs.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func load() -> [PlaybackProgress] {
        let data = kvs.data(forKey: Self.progressKey) ?? defaults.data(forKey: Self.progressKey)
        guard let data, let entries = try? JSONDecoder().decode([PlaybackProgress].self, from: data) else {
            return []
        }
        return entries
    }

    func save(_ entries: [PlaybackProgress]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        kvs.set(data, forKey: Self.progressKey)
        defaults.set(data, forKey: Self.progressKey)
    }
}
