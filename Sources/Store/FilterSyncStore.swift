import Foundation

/// Persists the hidden language / quality tags and Live TV lists in iCloud Key-Value Store so the filters follow
/// the user across iPhone, Mac and Apple TV. UserDefaults keeps a local copy, which also seeds
/// iCloud with the filters saved before they were synced (see `seedCloudIfNeeded`).
final class FilterSyncStore {
    struct Filters: Equatable {
        var hiddenLanguages: Set<String> = []
        var hiddenQualities: Set<String> = []
        /// Live TV categories, as `<provider id>|<category id>`.
        var hiddenLiveCategories: Set<String> = []
    }

    static let languagesKey = "iptv.hiddenLanguages"
    static let qualitiesKey = "iptv.hiddenQualities"
    static let liveCategoriesKey = "iptv.hiddenLiveCategories"
    private static let keys = [languagesKey, qualitiesKey, liveCategoriesKey]

    private let kvs = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard

    /// Called on the main queue when another device changed the filters.
    var onExternalChange: ((Filters) -> Void)?

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            guard changedKeys.map({ !Set($0).isDisjoint(with: Self.keys) }) ?? true else { return }
            self.onExternalChange?(self.load())
        }
        kvs.synchronize()
        seedCloudIfNeeded()
    }

    /// Filters chosen before they were synced only live in UserDefaults: push them to iCloud
    /// when it has none, so the other devices get them without waiting for a change.
    private func seedCloudIfNeeded() {
        for key in Self.keys where kvs.array(forKey: key) == nil {
            if let local = defaults.stringArray(forKey: key), !local.isEmpty {
                kvs.set(local, forKey: key)
            }
        }
        kvs.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func load() -> Filters {
        Filters(hiddenLanguages: tags(forKey: Self.languagesKey),
                hiddenQualities: tags(forKey: Self.qualitiesKey),
                hiddenLiveCategories: tags(forKey: Self.liveCategoriesKey))
    }

    func save(_ filters: Filters) {
        let values = [(Self.languagesKey, filters.hiddenLanguages), (Self.qualitiesKey, filters.hiddenQualities),
                      (Self.liveCategoriesKey, filters.hiddenLiveCategories)]
        for (key, tags) in values {
            kvs.set(tags.sorted(), forKey: key)
            defaults.set(tags.sorted(), forKey: key)
        }
    }

    private func tags(forKey key: String) -> Set<String> {
        Set((kvs.array(forKey: key) as? [String]) ?? defaults.stringArray(forKey: key) ?? [])
    }
}
