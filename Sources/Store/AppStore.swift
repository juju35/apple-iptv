import Foundation
import SwiftUI

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

    @Published private(set) var liveCategories: [ContentCategory] = []
    @Published private(set) var movieCategories: [ContentCategory] = []
    @Published private(set) var seriesCategories: [ContentCategory] = []
    @Published private(set) var liveItems: [MediaItem] = []
    @Published private(set) var movieItems: [MediaItem] = []
    @Published private(set) var seriesItems: [MediaItem] = []

    @Published var isLoading = false
    @Published var lastError: String?

    private var clients: [Provider.ID: IPTVClient] = [:]
    private let syncStore = ProviderSyncStore()

    private static let selectedKey = "iptv.selectedProvider"

    var selectedProvider: Provider? {
        providers.first { $0.id == selectedProviderID } ?? providers.first
    }

    init() {
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
        syncStore.save(providers)
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
        let client = IPTVClientFactory.client(for: provider)
        clients[provider.id] = client
        return client
    }

    // MARK: - Loading

    func reload() async {
        guard let provider = selectedProvider else {
            liveCategories = []; movieCategories = []; seriesCategories = []
            liveItems = []; movieItems = []; seriesItems = []
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

            liveCategories = (try? await liveCats) ?? []
            movieCategories = (try? await movieCats) ?? []
            seriesCategories = (try? await seriesCats) ?? []
            liveItems = (try? await live) ?? []
            movieItems = (try? await movies) ?? []
            seriesItems = (try? await series) ?? []
        } catch {
            lastError = error.localizedDescription
        }
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
