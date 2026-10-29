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
    /// Lists (categories) to hide, as `<provider id>|<kind>|<category id>` (see `CategoryListOption.key`).
    @Published var hiddenCategories: Set<String> {
        didSet { persistFilters(); applyFilters() }
    }
    /// Text removed from list names for display ("FR |", "VIP"…); synced through iCloud.
    @Published var listNameRemovals: [String] {
        didSet {
            if !Demo.isOn { listNameRemovalsSync.save(listNameRemovals) }
            applyFilters()
        }
    }
    private let listNameRemovalsSync = CloudStringListStore(key: CloudStringListStore.listNameRemovalsKey)
    /// The selected provider's lists of each kind, hidden ones included, offered in Settings.
    @Published private(set) var listOptions: [MediaKind: [CategoryListOption]] = [:]
    /// Tags found in the current provider's catalog, offered in Settings.
    @Published private(set) var languageOptions: [ContentTags.Option] = []
    @Published private(set) var qualityOptions: [ContentTags.Option] = []

    /// Everything the provider returned, before filtering.
    private var catalog = Catalog()
    /// Provider `catalog` belongs to, so switching providers doesn't show the previous lists.
    private var catalogProviderID: Provider.ID?
    /// When the shown lists were fetched from the provider (from the cache or just now).
    @Published private(set) var catalogUpdatedAt: Date?

    /// How long cached lists are used without asking the provider; 0 disables the cache.
    @Published var cacheLifetime: TimeInterval {
        didSet {
            UserDefaults.standard.set(cacheLifetime, forKey: Self.cacheLifetimeKey)
            if cacheLifetime == 0 { CatalogCache.removeAll() }
        }
    }
    private static let cacheLifetimeKey = "iptv.cacheLifetime"
    /// Visible items by id, to resolve Continue Watching entries and favorites.
    private var visibleItemsById: [String: MediaItem] = [:]

    /// Watch progress by `PlaybackProgress.key`, synced through iCloud.
    @Published private(set) var playbackProgress: [String: PlaybackProgress] = [:]
    private let progressSync = PlaybackProgressSyncStore()

    /// Favorite channels, movies and series (`MediaItem.id`s), most recently added first; synced through iCloud.
    @Published private(set) var favoriteIDs: [String] = []
    private let favoritesSync = CloudStringListStore(key: CloudStringListStore.favoritesKey)

    /// Live channels played lately (`MediaItem.id`s), most recent first; synced through iCloud.
    @Published private(set) var recentChannelIDs: [String] = []
    private let recentChannelsSync = CloudStringListStore(key: CloudStringListStore.recentChannelsKey)

    /// Subscription details by provider, refreshed when Settings opens and kept between launches.
    @Published var accountInfo: [Provider.ID: AccountInfo] =
        (UserDefaults.standard.data(forKey: "iptv.accountInfo"))
            .flatMap { try? JSONDecoder().decode([Provider.ID: AccountInfo].self, from: $0) } ?? [:]

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
        let filters = Demo.isOn ? FilterSyncStore.Filters() : filterSync.load()
        hiddenLanguages = filters.hiddenLanguages
        hiddenQualities = filters.hiddenQualities
        hiddenCategories = filters.hiddenCategories
        listNameRemovals = Demo.isOn ? [] : listNameRemovalsSync.load()
        cacheLifetime = UserDefaults.standard.object(forKey: Self.cacheLifetimeKey) as? TimeInterval
            ?? CatalogCache.defaultLifetime
        if !Demo.isOn {
            favoriteIDs = favoritesSync.load()
            favoritesSync.onExternalChange = { [weak self] remote in
                Task { @MainActor in
                    guard let self, self.favoriteIDs != remote else { return }
                    self.favoriteIDs = remote
                }
            }
            recentChannelIDs = recentChannelsSync.load()
            recentChannelsSync.onExternalChange = { [weak self] remote in
                Task { @MainActor in
                    guard let self, self.recentChannelIDs != remote else { return }
                    self.recentChannelIDs = remote
                }
            }
            listNameRemovalsSync.onExternalChange = { [weak self] remote in
                Task { @MainActor in
                    guard let self, self.listNameRemovals != remote else { return }
                    self.listNameRemovals = remote
                }
            }
            filterSync.onExternalChange = { [weak self] remote in
                Task { @MainActor in self?.applyExternal(remote) }
            }
            playbackProgress = PlaybackProgress.merged(progressSync.load(), into: [:])
            progressSync.onExternalChange = { [weak self] remote in
                Task { @MainActor in
                    guard let self else { return }
                    self.playbackProgress = PlaybackProgress.merged(remote, into: self.playbackProgress)
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
        filterSync.save(FilterSyncStore.Filters(hiddenLanguages: hiddenLanguages, hiddenQualities: hiddenQualities,
                                                hiddenCategories: hiddenCategories))
    }

    /// Applies filters changed on another device via iCloud.
    private func applyExternal(_ remote: FilterSyncStore.Filters) {
        if hiddenLanguages != remote.hiddenLanguages { hiddenLanguages = remote.hiddenLanguages }
        if hiddenQualities != remote.hiddenQualities { hiddenQualities = remote.hiddenQualities }
        if hiddenCategories != remote.hiddenCategories { hiddenCategories = remote.hiddenCategories }
    }

    /// Merges providers changed on another device via iCloud.
    private func applyExternal(_ remote: [Provider]) {
        guard remote != providers else { return }
        // Edited elsewhere (URL, credentials…): their cached lists may be wrong.
        for provider in remote where providers.first(where: { $0.id == provider.id }) != provider {
            CatalogCache.remove(providerID: provider.id)
        }
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
        CatalogCache.remove(providerID: provider.id)
        if provider.id == selectedProviderID { Task { await reload(force: true) } }
    }

    func removeProvider(_ provider: Provider) {
        providers.removeAll { $0.id == provider.id }
        clients[provider.id] = nil
        CatalogCache.remove(providerID: provider.id)
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

    /// Loads the selected provider's lists: from the cache while it is fresh, otherwise from the
    /// provider (an expired cache is shown meanwhile). `force` always asks the provider.
    func reload(force: Bool = false) async {
        guard let provider = selectedProvider else {
            catalog = Catalog()
            catalogProviderID = nil
            catalogUpdatedAt = nil
            applyFilters()
            return
        }
        if catalogProviderID != provider.id {
            // Don't keep showing another provider's lists.
            catalog = Catalog()
            catalogProviderID = provider.id
            catalogUpdatedAt = nil
            applyFilters()
        }
        let usesCache = cacheLifetime > 0 && !Demo.isOn
        if usesCache, !force, let cached = await CatalogCache.load(providerID: provider.id),
           selectedProvider?.id == provider.id {
            catalog = cached.catalog
            catalogUpdatedAt = cached.savedAt
            applyFilters()
            if Date().timeIntervalSince(cached.savedAt) < cacheLifetime { return }
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

            let fetched = Catalog(
                liveCategories: (try? await liveCats) ?? [],
                movieCategories: (try? await movieCats) ?? [],
                seriesCategories: (try? await seriesCats) ?? [],
                liveItems: (try? await live) ?? [],
                movieItems: (try? await movies) ?? [],
                seriesItems: (try? await series) ?? []
            )
            // The user may have switched providers while this one was loading.
            guard selectedProvider?.id == provider.id else { return }
            // An empty answer is more likely a portal hiccup than an empty catalog:
            // keep what is shown (and cached) rather than wiping it.
            if !fetched.isEmpty || catalog.isEmpty {
                catalog = fetched
                catalogUpdatedAt = Date()
                if usesCache, !fetched.isEmpty { CatalogCache.save(fetched, providerID: provider.id) }
            }
        } catch {
            lastError = error.localizedDescription
        }
        applyFilters()
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

// MARK: - Playback, favorites and progress

extension AppStore {
    // MARK: - Filters

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

        let removals = listNameRemovals
        func displayName(_ name: String) -> String { ContentTags.cleanedName(name, removing: removals) }
        func displayed(_ category: ContentCategory) -> ContentCategory {
            ContentCategory(id: category.id, name: displayName(category.name))
        }

        let provider = catalogProviderID
        let hiddenLists = hiddenCategories
        func isHiddenList(_ kind: MediaKind, _ categoryId: String) -> Bool {
            hiddenLists.contains(CategoryListOption.key(provider: provider, kind: kind, category: categoryId))
        }
        func listOptions(_ kind: MediaKind, _ categories: [ContentCategory], _ items: [MediaItem])
            -> [CategoryListOption] {
            let counts = Dictionary(items.flatMap(\.categoryIds).map { ($0, 1) }, uniquingKeysWith: +)
            return categories.map {
                CategoryListOption(key: CategoryListOption.key(provider: provider, kind: kind, category: $0.id),
                                   name: displayName($0.name), originalName: $0.name, count: counts[$0.id] ?? 0)
            }
        }
        self.listOptions = [
            .live: listOptions(.live, catalog.liveCategories, catalog.liveItems),
            .movie: listOptions(.movie, catalog.movieCategories, catalog.movieItems),
            .series: listOptions(.series, catalog.seriesCategories, catalog.seriesItems),
        ]

        let hiddenLanguages = hiddenLanguages
        let hiddenQualities = hiddenQualities
        func isVisible(_ item: MediaItem) -> Bool {
            // Hidden as soon as one of its lists is.
            if item.categoryIds.contains(where: { isHiddenList(item.kind, $0) }) { return false }
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

        liveCategories = catalog.liveCategories.filter { isVisible($0) && !isHiddenList(.live, $0.id) }.map(displayed)
        movieCategories = catalog.movieCategories.filter { isVisible($0) && !isHiddenList(.movie, $0.id) }
            .map(displayed)
        seriesCategories = catalog.seriesCategories.filter { isVisible($0) && !isHiddenList(.series, $0.id) }
            .map(displayed)
        liveItems = catalog.liveItems.filter(isVisible)
        movieItems = catalog.movieItems.filter(isVisible)
        seriesItems = catalog.seriesItems.filter(isVisible)
        visibleItemsById = Dictionary((liveItems + movieItems + seriesItems).map { ($0.id, $0) },
                                      uniquingKeysWith: { first, _ in first })
    }

    /// Resolves the stream URL of `item` (or of one of its episodes, through `ref`) for the player.
    func playbackRequest(for item: MediaItem, ref: String? = nil, containerExtension: String? = nil,
                         progress: PlaybackProgressContext? = nil, from start: Double = 0) async throws
        -> PlaybackRequest {
        guard let provider = selectedProvider else { throw IPTVError.invalidURL }
        let client = client(for: provider)
        let url = try await client.streamURL(
            kind: item.kind,
            playbackRef: ref ?? item.playbackRef,
            containerExtension: ref == nil ? item.containerExtension : containerExtension
        )
        var request = PlaybackRequest(url: url, title: item.name, headers: client.streamHeaders)
        request.progress = progress
        request.startPosition = start
        request.artworkURL = item.posterURL
        if item.kind == .live {
            request.channel = item
            recordRecentChannel(item)
            #if os(iOS)
            // Live channels play in VLC on iPhone and iPad, like movies and series often do: same controls
            // for everything (channel bar, tap to show), whatever the stream's format.
            request.engine = .vlc
            #endif
        }
        return request
    }

    // MARK: - Favorites

    func isFavorite(_ item: MediaItem) -> Bool {
        favoriteIDs.contains(item.id)
    }

    func toggleFavorite(_ item: MediaItem) {
        if let index = favoriteIDs.firstIndex(of: item.id) {
            favoriteIDs.remove(at: index)
        } else {
            favoriteIDs.insert(item.id, at: 0)
        }
        if !Demo.isOn { favoritesSync.save(favoriteIDs) }
    }

    /// Recently watched live channels that are still visible, most recent first.
    func recentChannels() -> [MediaItem] {
        recentChannelIDs.compactMap { visibleItemsById[$0] }
    }

    /// Puts `channel` first in the recently watched channels (20 kept).
    func recordRecentChannel(_ channel: MediaItem) {
        guard !Demo.isOn else { return }
        recentChannelIDs = Array(([channel.id] + recentChannelIDs.filter { $0 != channel.id }).prefix(20))
        recentChannelsSync.save(recentChannelIDs)
    }

    /// Visible favorites, most recently added first (`kind` nil for all kinds).
    func favorites(_ kind: MediaKind?) -> [MediaItem] {
        favoriteIDs.compactMap { visibleItemsById[$0] }.filter { kind == nil || $0.kind == kind }
    }

    // MARK: - Playback progress

    /// Unfinished progress for a movie or an episode.
    func progress(for key: String) -> PlaybackProgress? {
        playbackProgress[key].flatMap { $0.isFinished ? nil : $0 }
    }

    /// Whether a movie or episode was watched to the end.
    func isWatched(_ key: String) -> Bool {
        playbackProgress[key]?.isFinished == true
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
        playbackProgress = PlaybackProgress.pruned(playbackProgress)
        progressSync.save(Array(playbackProgress.values))
    }
}
