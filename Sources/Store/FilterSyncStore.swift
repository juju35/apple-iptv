import Foundation

/// Persists the hidden language / quality tags in iCloud Key-Value Store so the filters follow
/// the user across iPhone, Mac and Apple TV. UserDefaults keeps a local copy, which also seeds
/// iCloud with the filters saved before they were synced.
final class FilterSyncStore {
    struct Filters: Equatable {
        var hiddenLanguages: Set<String>
        var hiddenQualities: Set<String>
    }

    static let languagesKey = "iptv.hiddenLanguages"
    static let qualitiesKey = "iptv.hiddenQualities"

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
            guard changedKeys.map({ $0.contains(Self.languagesKey) || $0.contains(Self.qualitiesKey) }) ?? true
            else { return }
            self.onExternalChange?(self.load())
        }
        kvs.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func load() -> Filters {
        Filters(hiddenLanguages: tags(forKey: Self.languagesKey),
                hiddenQualities: tags(forKey: Self.qualitiesKey))
    }

    func save(_ filters: Filters) {
        for (key, tags) in [(Self.languagesKey, filters.hiddenLanguages), (Self.qualitiesKey, filters.hiddenQualities)] {
            kvs.set(tags.sorted(), forKey: key)
            defaults.set(tags.sorted(), forKey: key)
        }
    }

    private func tags(forKey key: String) -> Set<String> {
        Set((kvs.array(forKey: key) as? [String]) ?? defaults.stringArray(forKey: key) ?? [])
    }
}
