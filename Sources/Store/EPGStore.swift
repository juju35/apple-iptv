import Foundation

/// The selected provider's whole programme guide, by `MediaItem.id`, cached on disk for a
/// configurable time so channels show what's on without asking the provider again.
@MainActor
final class EPGStore: ObservableObject {
    @Published private(set) var guide: [String: [EPGEntry]] = [:]
    /// When the shown guide was downloaded.
    @Published private(set) var updatedAt: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    /// How long a downloaded guide is used before downloading it again; 0 turns the guide off
    /// (channels then only show the short per-channel guide).
    @Published var lifetime: TimeInterval {
        didSet {
            UserDefaults.standard.set(lifetime, forKey: Self.lifetimeKey)
            if lifetime == 0 {
                Cache.removeAll()
                guide = [:]
                updatedAt = nil
            }
        }
    }

    static let lifetimes: [(label: String, seconds: TimeInterval)] = [
        (String(localized: "Off"), 0),
        (String(localized: "3 hours"), 3 * 3600),
        (String(localized: "6 hours"), 6 * 3600),
        (String(localized: "12 hours"), 12 * 3600),
        (String(localized: "1 day"), 24 * 3600),
        (String(localized: "3 days"), 3 * 24 * 3600),
    ]
    private static let lifetimeKey = "iptv.epgLifetime"

    private var providerID: Provider.ID?

    init() {
        lifetime = UserDefaults.standard.object(forKey: Self.lifetimeKey) as? TimeInterval ?? 12 * 3600
    }

    /// Programmes of `channel`, from the whole guide.
    func entries(for channel: MediaItem) -> [EPGEntry] {
        guide[channel.id] ?? []
    }

    /// What `channel` is showing right now.
    func current(for channel: MediaItem, at date: Date = Date()) -> EPGEntry? {
        entries(for: channel).first { $0.start <= date && date < $0.end }
    }

    /// Loads the selected provider's guide: from the cache while it's fresh, otherwise from the
    /// provider (a stale cache is shown meanwhile). `force` always downloads it.
    func refresh(using store: AppStore, force: Bool = false) async {
        guard let provider = store.selectedProvider, lifetime > 0, !Demo.isOn else {
            guide = [:]
            updatedAt = nil
            return
        }
        if providerID != provider.id {
            providerID = provider.id
            guide = [:]
            updatedAt = nil
        }
        if !force, let cached = await Cache.load(providerID: provider.id), providerID == provider.id {
            guide = cached.guide
            updatedAt = cached.savedAt
            if Date().timeIntervalSince(cached.savedAt) < lifetime { return }
        }
        guard !isLoading, !store.liveItems.isEmpty else { return }
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            let fetched = try await store.client(for: provider).fullEPG(for: store.liveItems)
            guard providerID == provider.id else { return }
            // An empty answer most likely means the provider has no full guide: keep what is shown.
            if !fetched.isEmpty || guide.isEmpty {
                guide = fetched
                updatedAt = Date()
                if !fetched.isEmpty { Cache.save(fetched, providerID: provider.id) }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// One JSON file per provider in Caches/EPG.
    private enum Cache {
        struct Entry: Codable {
            let savedAt: Date
            let guide: [String: [EPGEntry]]
        }

        static func load(providerID: UUID) async -> Entry? {
            let url = fileURL(providerID)
            return await Task.detached(priority: .userInitiated) {
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Entry.self, from: data)
            }.value
        }

        static func save(_ guide: [String: [EPGEntry]], providerID: UUID) {
            let url = fileURL(providerID)
            let entry = Entry(savedAt: Date(), guide: guide)
            Task.detached(priority: .utility) {
                guard let data = try? JSONEncoder().encode(entry) else { return }
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try? data.write(to: url, options: .atomic)
            }
        }

        static func removeAll() {
            try? FileManager.default.removeItem(at: directory)
        }

        private static var directory: URL {
            URL.cachesDirectory.appending(path: "EPG", directoryHint: .isDirectory)
        }

        private static func fileURL(_ providerID: UUID) -> URL {
            directory.appending(path: "\(providerID.uuidString).json")
        }
    }
}
