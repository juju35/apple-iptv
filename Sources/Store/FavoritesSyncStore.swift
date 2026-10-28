import Foundation

/// Persists favorite channels, movies and series (`MediaItem.id`s, most recently added first)
/// in iCloud Key-Value Store, with a UserDefaults copy for when iCloud is unavailable.
final class FavoritesSyncStore {
    static let favoritesKey = "iptv.favorites"

    private let kvs = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard

    /// Called on the main queue when another device changed the favorites.
    var onExternalChange: (([String]) -> Void)?

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            guard changedKeys?.contains(Self.favoritesKey) ?? true else { return }
            self.onExternalChange?(self.load())
        }
        kvs.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func load() -> [String] {
        (kvs.array(forKey: Self.favoritesKey) as? [String]) ?? defaults.stringArray(forKey: Self.favoritesKey) ?? []
    }

    func save(_ ids: [String]) {
        kvs.set(ids, forKey: Self.favoritesKey)
        defaults.set(ids, forKey: Self.favoritesKey)
    }
}
