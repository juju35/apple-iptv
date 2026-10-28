import Combine
import Foundation

/// Central observable store: providers, their clients, and loaded content.
@MainActor
final class AppStore: ObservableObject {
    @Published var providers: [Provider] = [] {
        didSet { persistProviders() }
    }
    @Published var selectedProviderID: Provider.ID? {
        didSet {
            UserDefaults.standard.set(selectedProviderID?.uuidString, forKey: Self.selectedKey)
            Task { await reload() }
        }
    }

    // Content after the language / quality filters; the unfiltered catalog is in `catalog`.
    @Published private(set) var liveCategories: [ContentCategory] = []
    @Published private(set) var movieCategories: [ContentCategory] = []
    @Published private(set) var seriesCategories: [ContentCategory] = []
    @Published private(set) var liveItems: [MediaItem] = []
    @Published private(set) var movieItems: [MediaItem] = []
    @Published private(set) var seriesItems: [MediaItem] = []

    /// Languages to hide, matched against category names and item names (see `ContentTags`).
    @Published var hiddenLanguages: Set<String> {
        didSet { persistFilters(); applyFilters() }
    }
    /// Live channel qualities to hide.
    @Published var hiddenQualities: Set<String> {
        didSet { persistFilters(); applyFilters() }
    }
    /// Tags found in the current provider's catalog, offered in Settings.
    @Published private(set) var languageOptions: [ContentTags.Option] = []
    @Published private(set) var qualityOptions: [ContentTags.Option] = []

    private var catalog = Catalog()
    /// Visible items by id, to resolve Continue Watching entries.
    private var visibleItemsById: [String: MediaItem] = [:]

    /// Watch progress by `PlaybackProgress.key`, synced through iCloud.
    @Published private(set) var playbackProgress: [String: PlaybackProgress] = [:]
    private let progressSync = PlaybackProgressSyncStore()

    @Published var isLoading = false
    @Published var lastError: String?

    private var clients: [Provider.ID: IPTVClient] = [:]
    private let syncStore = ProviderSyncStore()

    private static let selectedKey = "iptv.selectedProvider"
    private let filterSync = FilterSyncStore()

    var selectedProvider: Provider? {
        providers.first { $0.id == selectedProviderID } ?? providers.first
    }

    init() {
        // Screenshot mode shows everything and leaves the user's iCloud filters alone.
        let filters = Demo.isOn ? FilterSyncStore.Filters(hiddenLanguages: [], hiddenQualities: [])
                                : filterSync.load()
        hiddenLanguages = filters.hiddenLanguages
        hiddenQualities = filters.hiddenQualities
        if !Demo.isOn {
            filterSync.onExternalChange = { [weak self] remote in
                Task { @MainActor in self?.applyExternal(remote) }
            }
            playbackProgress = Self.merged(progressSync.load(), into: [:])
            progressSync.onExternalChange = { [weak self] remote in
                Task { @MainActor in
                    guard let self else { return }
                    self.playbackProgress = Self.merged(remote, into: self.playbackProgress)
                }
            }
        }
        if Demo.isOn {
            // Screenshot mode: one made-up provider, nothing read from or written to iCloud.
            providers = [Demo.provider]
            selectedProviderID = Demo.provider.id
            return
        }
        providers = syncStore.load()
        if let raw = UserDefaults.standard.string(forKey: Self.selectedKey),
           let id = UUID(uuidString: raw) {
            selectedProviderID = id
        } else {
            selectedProviderID = providers.first?.id
        }
        syncStore.onExternalChange = { [weak self] remote in
            Task { @MainActor in self?.applyExternal(remote) }
        }
    }

    // MARK: - Persistence (iCloud KVS + UserDefaults fallback)

    private func persistProviders() {
        guard !Demo.isOn else { return }
        syncStore.save(providers)
    }

    private func persistFilters() {
        guard !Demo.isOn else { return }
        filterSync.save(FilterSyncStore.Filters(hiddenLanguages: hiddenLanguages, hiddenQualities: hiddenQualities))
    }

    /// Applies filters changed on another device via iCloud.
    private func applyExternal(_ remote: FilterSyncStore.Filters) {
        if hiddenLanguages != remote.hiddenLanguages { hiddenLanguages = remote.hiddenLanguages }
        if hiddenQualities != remote.hiddenQualities { hiddenQualities = remote.hiddenQualities }
    }

    /// Merges providers changed on another device via iCloud.
    private func applyExternal(_ remote: [Provider]) {
        guard remote != providers else { return }
        clients.removeAll()
        providers = remote
        if let selected = selectedProviderID, !remote.contains(where: { $0.id == selected }) {
            selectedProviderID = remote.first?.id
        } else {
            Task { await reload() }
        }
    }

    // MARK: - Providers

    func addProvider(_ provider: Provider) {
        providers.append(provider)
        if selectedProviderID == nil { selectedProviderID = provider.id }
    }

    func updateProvider(_ provider: Provider) {
        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        providers[index] = provider
        clients[provider.id] = nil
        if provider.id == selectedProviderID { Task { await reload() } }
    }

    func removeProvider(_ provider: Provider) {
        providers.removeAll { $0.id == provider.id }
        clients[provider.id] = nil
        if selectedProviderID == provider.id {
            selectedProviderID = providers.first?.id
        }
    }

    func client(for provider: Provider) -> IPTVClient {
        if let existing = clients[provider.id] { return existing }
        let client: IPTVClient = Demo.isOn ? DemoClient() : IPTVClientFactory.client(for: provider)
        clients[provider.id] = client
        return client
    }

    // MARK: - Loading

    func reload() async {
        guard let provider = selectedProvider else {
            catalog = Catalog()
            applyFilters()
            return
        }
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let client = client(for: provider)
        do {
            try await client.authenticate()
            async let liveCats = client.categories(for: .live)
            async let movieCats = client.categories(for: .movie)
            async let seriesCats = client.categories(for: .series)
            async let live = client.items(kind: .live, categoryId: nil)
            async let movies = client.items(kind: .movie, categoryId: nil)
            async let series = client.items(kind: .series, categoryId: nil)

            catalog = Catalog(
                liveCategories: (try? await liveCats) ?? [],
                movieCategories: (try? await movieCats) ?? [],
                seriesCategories: (try? await seriesCats) ?? [],
                liveItems: (try? await live) ?? [],
                movieItems: (try? await movies) ?? [],
                seriesItems: (try? await series) ?? []
            )
        } catch {
            lastError = error.localizedDescription
        }
        applyFilters()
    }

    // MARK: - Filters

    /// Everything the provider returned, before filtering.
    private struct Catalog {
        var liveCategories: [ContentCategory] = []
        var movieCategories: [ContentCategory] = []
        var seriesCategories: [ContentCategory] = []
        var liveItems: [MediaItem] = []
        var movieItems: [MediaItem] = []
        var seriesItems: [MediaItem] = []
    }

    /// Recomputes the published content and the available tags from `catalog`.
    private func applyFilters() {
        let all = [catalog.liveCategories, catalog.movieCategories, catalog.seriesCategories]
        let categoryLanguage: [String: String] = Dictionary(
            all.joined().compactMap { category in
                ContentTags.language(of: category.name).map { (category.id, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        // An item's own tag ("… (VOSTFR)") wins over its category's ("FR | Movies").
        func language(of item: MediaItem) -> String? {
            ContentTags.language(of: item.name) ?? item.categoryId.flatMap { categoryLanguage[$0] }
        }

        let allItems = catalog.liveItems + catalog.movieItems + catalog.seriesItems
        languageOptions = ContentTags.options(allItems.compactMap(language(of:)))
        qualityOptions = ContentTags.options(catalog.liveItems.compactMap { ContentTags.quality(of: $0.name) })

        let hiddenLanguages = hiddenLanguages
        let hiddenQualities = hiddenQualities
        func isVisible(_ item: MediaItem) -> Bool {
            if let tag = language(of: item), hiddenLanguages.contains(tag) { return false }
            if item.kind == .live, let tag = ContentTags.quality(of: item.name), hiddenQualities.contains(tag) {
                return false
            }
            return true
        }
        func isVisible(_ category: ContentCategory) -> Bool {
            guard let tag = categoryLanguage[category.id] else { return true }
            return !hiddenLanguages.contains(tag)
        }

        liveCategories = catalog.liveCategories.filter(isVisible)
        movieCategories = catalog.movieCategories.filter(isVisible)
        seriesCategories = catalog.seriesCategories.filter(isVisible)
        liveItems = catalog.liveItems.filter(isVisible)
        movieItems = catalog.movieItems.filter(isVisible)
        seriesItems = catalog.seriesItems.filter(isVisible)
        visibleItemsById = Dictionary((movieItems + seriesItems).map { ($0.id, $0) },
                                      uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Playback progress

    /// A movie or series being watched, with its most recent progress.
    struct ContinueWatchingEntry: Identifiable {
        let item: MediaItem
        let progress: PlaybackProgress
        var id: String { item.id }
    }

    /// Unfinished progress for a movie or an episode.
    func progress(for key: String) -> PlaybackProgress? {
        playbackProgress[key].flatMap { $0.isFinished ? nil : $0 }
    }

    /// The most recently watched, unfinished episode of a series.
    func latestEpisodeProgress(forSeries itemId: String) -> PlaybackProgress? {
        playbackProgress.values
            .filter { $0.itemId == itemId && $0.episodeId != nil && !$0.isFinished }
            .max { $0.updatedAt < $1.updatedAt }
    }

    /// Started movies and series, most recent first (`kind` nil for both).
    func continueWatching(_ kind: MediaKind?) -> [ContinueWatchingEntry] {
        var seen: Set<String> = []
        return playbackProgress.values
            .filter { !$0.isFinished }
            .sorted { $0.updatedAt > $1.updatedAt }
            .compactMap { progress in
                guard let item = visibleItemsById[progress.itemId], kind == nil || item.kind == kind,
                      seen.insert(item.id).inserted else { return nil }
                return ContinueWatchingEntry(item: item, progress: progress)
            }
    }

    /// Saves where playback is; called periodically by the players and when they close.
    func recordProgress(_ context: PlaybackProgressContext, position: Double, duration: Double) {
        // Live streams and unknown durations have nothing to resume.
        guard !Demo.isOn, position.isFinite, duration.isFinite, duration > 60 else { return }
        let existing = playbackProgress[context.key]
        // Barely started: not worth a Continue Watching entry.
        guard position >= 10 || existing != nil else { return }
        playbackProgress[context.key] = PlaybackProgress(
            key: context.key,
            itemId: context.itemId,
            episodeId: context.episodeId,
            season: context.season,
            episode: context.episode,
            position: position,
            duration: duration,
            updatedAt: Date(),
            isFinished: position / duration >= 0.95
        )
        playbackProgress = Self.pruned(playbackProgress)
        progressSync.save(Array(playbackProgress.values))
    }

    /// Union of both sides, the most recent entry winning for each key.
    private static func merged(_ entries: [PlaybackProgress],
                               into current: [String: PlaybackProgress]) -> [String: PlaybackProgress] {
        var result = current
        for entry in entries where (result[entry.key]?.updatedAt ?? .distantPast) < entry.updatedAt {
            result[entry.key] = entry
        }
        return pruned(result)
    }

    /// Keeps the store well under the iCloud key-value quota: finished entries for 30 days,
    /// and the 300 most recent overall.
    private static func pruned(_ entries: [String: PlaybackProgress]) -> [String: PlaybackProgress] {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let kept = entries.values
            .filter { !$0.isFinished || $0.updatedAt > cutoff }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(300)
        return Dictionary(kept.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func items(for kind: MediaKind) -> [MediaItem] {
        switch kind {
        case .live: return liveItems
        case .movie: return movieItems
        case .series: return seriesItems
        }
    }

    func categories(for kind: MediaKind) -> [ContentCategory] {
        switch kind {
        case .live: return liveCategories
        case .movie: return movieCategories
        case .series: return seriesCategories
        }
    }

    func categoryName(_ id: String?, kind: MediaKind) -> String {
        guard let id else { return "Other" }
        return categories(for: kind).first { $0.id == id }?.name ?? "Other"
    }
}
