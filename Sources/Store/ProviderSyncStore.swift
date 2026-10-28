import Foundation

/// Persists providers in iCloud Key-Value Store so accounts sync across
/// iPhone, Mac and Apple TV. Falls back to UserDefaults when iCloud is
/// unavailable. The *selected* provider stays local to each device.
final class ProviderSyncStore {
    static let providersKey = "iptv.providers"

    private let kvs = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard

    /// Called on the main queue when another device changed the providers.
    var onExternalChange: (([Provider]) -> Void)?

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            guard changedKeys?.contains(Self.providersKey) ?? true else { return }
            self.onExternalChange?(self.load())
        }
        kvs.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func load() -> [Provider] {
        let data = kvs.data(forKey: Self.providersKey) ?? defaults.data(forKey: Self.providersKey)
        guard let data, let providers = try? JSONDecoder().decode([Provider].self, from: data) else {
            return []
        }
        return providers
    }

    func save(_ providers: [Provider]) {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        kvs.set(data, forKey: Self.providersKey)
        kvs.synchronize()
        defaults.set(data, forKey: Self.providersKey)
    }
}
