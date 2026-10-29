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
                        MediaRow(title: String(localized: "Favorites"), items: favorites) { selectedItem = $0 }
                    }

                    let recentChannels = store.recentChannels()
                    if !recentChannels.isEmpty {
                        MediaRow(title: String(localized: "Recently Watched Channels"), items: recentChannels) { selectedItem = $0 }
                    }

                    if !store.liveItems.isEmpty {
                        MediaRow(title: String(localized: "Live TV"), items: Array(store.liveItems.prefix(25))) {
                            selectedItem = $0
                        }
                    }
                    if !store.movieItems.isEmpty {
                        MediaRow(title: String(localized: "Movies"), items: Array(store.movieItems.prefix(25))) {
                            selectedItem = $0
                        }
                        ForEach(store.movieCategories.prefix(6)) { category in
                            let items = store.movieItems.filter { $0.belongs(to: category.id) }
                            if !items.isEmpty {
                                MediaRow(title: category.name, items: Array(items.prefix(25))) {
                                    selectedItem = $0
                                }
                            }
                        }
                    }
                    if !store.seriesItems.isEmpty {
                        MediaRow(title: String(localized: "Series"), items: Array(store.seriesItems.prefix(25))) {
                            selectedItem = $0
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .background(Theme.background.ignoresSafeArea())
            .refreshableIfSupported { await store.reload(force: true) }
            .providerToolbar()
            .detailPresentation(item: $selectedItem) { item in
                MediaDetailView(item: item)
            }
        }
    }
}

struct HeroBanner: View {
    let item: MediaItem
    let onPlay: () -> Void

    private var artwork: some View {
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
    }

    var body: some View {
        #if os(tvOS)
        tvBody
        #else
        ZStack(alignment: .bottomLeading) {
            artwork

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
                .primaryActionStyle()
            }
            .padding(24)
        }
        #endif
    }

    #if os(tvOS)
    /// Apple TV top shelf style: edge-to-edge artwork, shaded from the left and the bottom, the title and a
    /// single system button over it.
    private var tvBody: some View {
        ZStack(alignment: .bottomLeading) {
            artwork
            LinearGradient(colors: [Theme.background.opacity(0.9), .clear],
                           startPoint: .leading, endPoint: .center)
            LinearGradient(colors: [.clear, Theme.background],
                           startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 18) {
                Text(item.name)
                    .font(.title.weight(.bold))
                    .lineLimit(2)
                if !metadata.isEmpty {
                    Text(metadata)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                if let plot = item.plot, !plot.isEmpty {
                    Text(plot)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                }
                Button(action: onPlay) {
                    Label("Play", systemImage: "play.fill")
                }
                .primaryActionStyle()
                .padding(.top, 8)
            }
            .frame(maxWidth: 1000, alignment: .leading)
            .padding(.horizontal, 80)
            .padding(.bottom, 50)
        }
        .ignoresSafeArea(edges: [.top, .horizontal])
    }

    /// "2025 · ★ 4.3 · Movie".
    private var metadata: String {
        var parts: [String] = []
        if let year = item.year, !year.isEmpty { parts.append(year) }
        if let rating = item.rating, rating > 0 { parts.append("★ " + String(format: "%.1f", rating)) }
        switch item.kind {
        case .movie: parts.append(String(localized: "Movie"))
        case .series: parts.append(String(localized: "Series"))
        case .live: parts.append(String(localized: "Live"))
        }
        return parts.joined(separator: " · ")
    }
    #endif
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
