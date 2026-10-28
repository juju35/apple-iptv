import Foundation

/// Persists the hidden language / quality tags and lists (categories) in iCloud Key-Value Store so the filters follow
/// the user across iPhone, Mac and Apple TV. UserDefaults keeps a local copy, which also seeds
/// iCloud with the filters saved before they were synced (see `seedCloudIfNeeded`).
final class FilterSyncStore {
    struct Filters: Equatable {
        var hiddenLanguages: Set<String> = []
        var hiddenQualities: Set<String> = []
        /// Categories (lists), as `<provider id>|<kind>|<category id>` (see `CategoryListOption.key`).
        var hiddenCategories: Set<String> = []
    }

    static let languagesKey = "iptv.hiddenLanguages"
    static let qualitiesKey = "iptv.hiddenQualities"
    static let categoriesKey = "iptv.hiddenCategories"
    /// Live TV lists only, as `<provider id>|<category id>`; read once into `categoriesKey`.
    private static let legacyLiveCategoriesKey = "iptv.hiddenLiveCategories"
    private static let keys = [languagesKey, qualitiesKey, categoriesKey]

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
                hiddenCategories: tags(forKey: Self.categoriesKey).union(legacyLiveCategories()))
    }

    /// The Live TV lists hidden before movie and series lists could be: `<provider>|<category>`
    /// becomes `<provider>|live|<category>`.
    private func legacyLiveCategories() -> Set<String> {
        Set(tags(forKey: Self.legacyLiveCategoriesKey).compactMap { key in
            guard let separator = key.firstIndex(of: "|") else { return nil }
            return "\(key[..<separator])|live\(key[separator...])"
        })
    }

    func save(_ filters: Filters) {
        let values = [(Self.languagesKey, filters.hiddenLanguages), (Self.qualitiesKey, filters.hiddenQualities),
                      (Self.categoriesKey, filters.hiddenCategories)]
        for (key, tags) in values {
            kvs.set(tags.sorted(), forKey: key)
            defaults.set(tags.sorted(), forKey: key)
        }
        // Migrated into `categoriesKey`.
        kvs.removeObject(forKey: Self.legacyLiveCategoriesKey)
        defaults.removeObject(forKey: Self.legacyLiveCategoriesKey)
    }

    private func tags(forKey key: String) -> Set<String> {
        Set((kvs.array(forKey: key) as? [String]) ?? defaults.stringArray(forKey: key) ?? [])
    }
}

/// A list (category) of the selected provider, for Settings.
struct CategoryListOption: Identifiable, Hashable {
    /// `<provider id>|<kind>|<category id>`: category ids are only unique within a provider and a kind.
    let key: String
    /// Shown name, without the text removed from list names.
    let name: String
    /// Name as the provider sends it.
    let originalName: String
    /// Items in the list, before the other filters.
    let count: Int
    var id: String { key }

    static func key(provider: UUID?, kind: MediaKind, category: String) -> String {
        "\(provider?.uuidString ?? "")|\(kind.rawValue)|\(category)"
    }
}
