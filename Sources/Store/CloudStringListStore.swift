import Foundation

/// A list of strings (`MediaItem.id`s of favorites and recent channels, text removed from list names) persisted in
/// iCloud Key-Value Store under `key`, with a UserDefaults copy for when iCloud is unavailable.
final class CloudStringListStore {
    static let favoritesKey = "iptv.favorites"
    static let recentChannelsKey = "iptv.recentChannels"
    static let listNameRemovalsKey = "iptv.listNameRemovals"

    let key: String

    private let kvs = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard

    /// Called on the main queue when another device changed the list.
    var onExternalChange: (([String]) -> Void)?

    private var observer: NSObjectProtocol?

    init(key: String) {
        self.key = key
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            guard changedKeys?.contains(self.key) ?? true else { return }
            self.onExternalChange?(self.load())
        }
        kvs.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func load() -> [String] {
        (kvs.array(forKey: key) as? [String]) ?? defaults.stringArray(forKey: key) ?? []
    }

    func save(_ values: [String]) {
        kvs.set(values, forKey: key)
        defaults.set(values, forKey: key)
    }
}
