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
    private var onCloudReady: (() -> Void)?

    /// On a fresh install the key-value store starts empty and iCloud's copy only arrives a little
    /// later (`didChangeExternallyNotification`): until then there is nothing to show yet, rather than
    /// no providers at all.
    private(set) var isAwaitingCloud: Bool

    /// Whether this device has seen iCloud's providers yet. Until it has, providers added here are
    /// merged with iCloud's when they arrive instead of replacing them on every other device.
    private var hasCloudCopy: Bool

    private var observer: NSObjectProtocol?

    init() {
        let signedIn = FileManager.default.ubiquityIdentityToken != nil
        hasCloudCopy = kvs.data(forKey: Self.providersKey) != nil
        isAwaitingCloud = signedIn && !hasCloudCopy && defaults.data(forKey: Self.providersKey) == nil
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs,
            queue: .main
        ) { [weak self] notification in
            self?.handleExternalChange(notification)
        }
        kvs.synchronize()
        seedCloudIfNeeded()
    }

    /// Calls `onReady` on the main queue once iCloud answers for the first time, or after `timeout` as it may
    /// never answer (nothing saved yet, offline). Returns false when there is nothing to wait for.
    func waitForCloud(timeout: TimeInterval, onReady: @escaping () -> Void) -> Bool {
        guard isAwaitingCloud else { return false }
        onCloudReady = onReady
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.endWaitingForCloud() }
        return true
    }

    /// Asks iCloud again (onboarding's "Reload from iCloud"), then waits for it as `waitForCloud` does.
    func reloadFromCloud(timeout: TimeInterval, onReady: @escaping () -> Void) {
        isAwaitingCloud = true
        _ = waitForCloud(timeout: timeout, onReady: onReady)
        kvs.synchronize()
    }

    private func endWaitingForCloud() {
        guard isAwaitingCloud else { return }
        isAwaitingCloud = false
        onCloudReady?()
        onCloudReady = nil
    }

    private func handleExternalChange(_ notification: Notification) {
        let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        if changedKeys?.contains(Self.providersKey) ?? true {
            if !hasCloudCopy, let merged = mergedWithLocal() {
                // First copy from iCloud: keep the providers added here before it came.
                save(merged)
            } else if let data = kvs.data(forKey: Self.providersKey) {
                defaults.set(data, forKey: Self.providersKey)
            }
            hasCloudCopy = hasCloudCopy || kvs.data(forKey: Self.providersKey) != nil
            onExternalChange?(load())
        }
        endWaitingForCloud()
    }

    /// iCloud's providers followed by the local ones it doesn't have, or nil when it has them all.
    private func mergedWithLocal() -> [Provider]? {
        let remote = decode(kvs.data(forKey: Self.providersKey))
        let missing = decode(defaults.data(forKey: Self.providersKey))
            .filter { local in !remote.contains { $0.id == local.id } }
        return missing.isEmpty ? nil : remote + missing
    }

    /// Providers saved before iCloud sync existed only live in UserDefaults, and `save` only runs on
    /// changes: push them to iCloud when it has none, so other devices (e.g. a new Apple TV) get them.
    private func seedCloudIfNeeded() {
        guard kvs.data(forKey: Self.providersKey) == nil,
              let local = defaults.data(forKey: Self.providersKey), !decode(local).isEmpty
        else { return }
        kvs.set(local, forKey: Self.providersKey)
        kvs.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func load() -> [Provider] {
        decode(kvs.data(forKey: Self.providersKey) ?? defaults.data(forKey: Self.providersKey))
    }

    func save(_ providers: [Provider]) {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        kvs.set(data, forKey: Self.providersKey)
        kvs.synchronize()
        defaults.set(data, forKey: Self.providersKey)
    }

    private func decode(_ data: Data?) -> [Provider] {
        guard let data, let providers = try? JSONDecoder().decode([Provider].self, from: data) else { return [] }
        return providers
    }
}
