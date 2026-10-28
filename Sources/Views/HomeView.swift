import SwiftUI

/// Netflix-style landing page: hero banner + horizontal carousels.
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedItem: MediaItem?

    private var heroItem: MediaItem? {
        store.movieItems.first { $0.posterURL != nil } ?? store.movieItems.first ?? store.seriesItems.first
            ?? store.liveItems.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let hero = heroItem {
                        HeroBanner(item: hero) { selectedItem = hero }
                    }

                    if store.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }

                    if let error = store.lastError {
                        ErrorBanner(message: error) { Task { await store.reload(force: true) } }
                    }

                    ContinueWatchingRow(entries: store.continueWatching(nil)) { selectedItem = $0 }

                    let favorites = store.favorites(nil)
                    if !favorites.isEmpty {
                        MediaRow(title: "Favorites", items: favorites) { selectedItem = $0 }
                    }

                    if !store.liveItems.isEmpty {
                        MediaRow(title: "Live TV", items: Array(store.liveItems.prefix(25))) {
                            selectedItem = $0
                        }
                    }
                    if !store.movieItems.isEmpty {
                        MediaRow(title: "Movies", items: Array(store.movieItems.prefix(25))) {
                            selectedItem = $0
                        }
                        ForEach(store.movieCategories.prefix(6)) { category in
                            let items = store.movieItems.filter { $0.categoryId == category.id }
                            if !items.isEmpty {
                                MediaRow(title: category.name, items: Array(items.prefix(25))) {
                                    selectedItem = $0
                                }
                            }
                        }
                    }
                    if !store.seriesItems.isEmpty {
                        MediaRow(title: "Series", items: Array(store.seriesItems.prefix(25))) {
                            selectedItem = $0
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .background(Theme.background.ignoresSafeArea())
            .refreshableIfSupported { await store.reload(force: true) }
            .providerToolbar()
            .sheet(item: $selectedItem) { item in
                MediaDetailView(item: item)
            }
        }
    }
}

struct HeroBanner: View {
    let item: MediaItem
    let onPlay: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: item.posterURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    GeneratedArtwork(title: item.name, kind: item.kind, showsTitle: false)
                }
            }
            .frame(height: Theme.heroHeight)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [.clear, Theme.background.opacity(0.85), Theme.background],
                startPoint: .center, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 12) {
                Text(item.name)
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(2)
                if let plot = item.plot, !plot.isEmpty {
                    Text(plot)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Button(action: onPlay) {
                    Label("Play", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .padding(24)
        }
    }
}

struct ErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
            Button("Retry", action: retry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

extension View {
    @ViewBuilder
    func refreshableIfSupported(_ action: @escaping @Sendable () async -> Void) -> some View {
        #if os(iOS)
        self.refreshable(action: action)
        #else
        self
        #endif
    }
}
