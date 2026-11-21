import SwiftUI

/// What Home presents: a title's detail, possibly starting it straight away (the banner's Play).
struct DetailSelection: Identifiable {
    let item: MediaItem
    var autoplay = false
    var id: String { item.id + (autoplay ? "#play" : "") }
}

/// One shelf of Home, worked out once per catalogue change rather than on every redraw.
struct HomeRow: Identifiable, Hashable {
    let id: String
    let title: String
    let kind: MediaKind
    /// The list "See All" opens; nil for a catch-all row (all the series).
    let categoryId: String?
    let items: [MediaItem]
    var isRanked = false

    static func == (lhs: HomeRow, rhs: HomeRow) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Netflix-style landing page: a featured title, then Continue Watching, My List, the movie and series lists
/// and their Top 10. On Apple TV, the billboard above the rows follows the focused poster.
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var layout: HomeLayoutStore
    @State private var selection: DetailSelection?
    @State private var seeAll: HomeRow?

    @State private var rows: [HomeRow] = []
    @State private var hero: MediaItem?
    #if os(tvOS)
    /// The poster under the focus, and (a moment later, so quick moves don't flicker) the billboard's title.
    @State private var focused: MediaItem?
    @State private var billboard: MediaItem?
    #endif

    private static let rowLength = 25

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Larger posters on iPad, where the phone's leave the screen half empty.
    private var rowPosterWidth: CGFloat { sizeClass == .regular ? 160 : Theme.rowPosterWidth }
    #else
    private var rowPosterWidth: CGFloat { Theme.rowPosterWidth }
    #endif

    /// What the rows are built from: a new catalogue, other filters or other chosen lists.
    private struct Inputs: Hashable {
        let updatedAt: Date?
        let movies: Int
        let series: Int
        let firstMovie: String?
        let firstSeries: String?
        let lists: [String]
        let categories: Int
    }

    private var inputs: Inputs {
        Inputs(updatedAt: store.catalogUpdatedAt, movies: store.movieItems.count, series: store.seriesItems.count,
               firstMovie: store.movieItems.first?.id, firstSeries: store.seriesItems.first?.id,
               lists: layout.listKeys, categories: store.movieCategories.count + store.seriesCategories.count)
    }

    /// Nothing to show yet: launch or a provider switch, before its lists arrive.
    private var isWaitingForCatalog: Bool {
        store.isLoading && store.liveItems.isEmpty && store.movieItems.isEmpty && store.seriesItems.isEmpty
    }

    var body: some View {
        NavigationStack {
            content
                .background(Theme.background.ignoresSafeArea())
                .refreshableIfSupported { await store.reload(force: true) }
                .providerToolbar(barHasTitle: false)
                .navigationDestination(item: $seeAll) { row in
                    HomeListGrid(row: row) { selection = DetailSelection(item: $0) }
                }
                .detailPresentation(item: $selection) { selection in
                    MediaDetailView(item: selection.item, autoplay: selection.autoplay)
                }
                .onChange(of: inputs, initial: true) { rebuild() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isWaitingForCatalog {
            // In place of Home only: the tabs and the provider switcher stay.
            HomeSkeleton(posterWidth: rowPosterWidth)
        } else {
            #if os(tvOS)
            tvContent
            #else
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if let hero {
                        HeroBanner(item: hero,
                                   onPlay: { selection = DetailSelection(item: hero, autoplay: true) },
                                   onInfo: { selection = DetailSelection(item: hero) })
                    }
                    shelves
                }
                .padding(.bottom, 40)
            }
            #if os(iOS)
            // The banner runs under the navigation bar, which stays clear until the page scrolls.
            .ignoresSafeArea(edges: hero == nil ? Edge.Set() : .top)
            #endif
            #endif
        }
    }

    /// Everything under the banner.
    @ViewBuilder
    private var shelves: some View {
        if let error = store.lastError {
            ErrorBanner(message: error) { Task { await store.reload(force: true) } }
        }

        ContinueWatchingRow(entries: store.continueWatching(nil), posterWidth: rowPosterWidth) {
            selection = DetailSelection(item: $0)
        }

        let favorites = store.favorites(nil).filter { $0.kind != .live }
        if !favorites.isEmpty {
            MediaRow(title: String(localized: "My List"), items: favorites, posterWidth: rowPosterWidth) {
                selection = DetailSelection(item: $0)
            }
        }

        ForEach(rows) { row in
            MediaRow(title: row.title, items: row.items, posterWidth: rowPosterWidth, isRanked: row.isRanked,
                     onSeeAll: row.isRanked ? nil : { seeAll = row }) {
                selection = DetailSelection(item: $0)
            }
        }
    }

    // MARK: - Rows

    private func rebuild() {
        rows = Self.buildRows(store: store, layout: layout)
        // Keep the featured title while it is still in the catalogue: it doesn't change under the user.
        let candidates = (store.movieItems + store.seriesItems).filter { $0.posterURL != nil }
        if hero.map({ current in candidates.contains { $0.id == current.id } }) != true {
            let withPlot = candidates.prefix(200).filter { !($0.plot?.isEmpty ?? true) }
            hero = withPlot.randomElement() ?? candidates.prefix(50).randomElement()
                ?? store.movieItems.first ?? store.seriesItems.first
        }
        #if os(tvOS)
        if billboard == nil || focused == nil { billboard = rows.first?.items.first ?? hero }
        #endif
    }

    /// The lists chosen in Settings › Home lists, else the first six movie lists and all the series; each kind's
    /// Top 10 (by the provider's rating) after its first row.
    private static func buildRows(store: AppStore, layout: HomeLayoutStore) -> [HomeRow] {
        var rows: [HomeRow] = []
        for kind in [MediaKind.movie, .series] {
            let items = store.items(for: kind)
            guard !items.isEmpty else { continue }
            // One pass over the catalogue, rather than a filter per row.
            var byList: [String: [MediaItem]] = [:]
            for item in items {
                for id in item.categoryIds where byList[id, default: []].count < rowLength {
                    byList[id, default: []].append(item)
                }
            }
            var kindRows: [HomeRow] = []
            if let chosen = layout.chosen(among: store.listOptions[kind] ?? []) {
                for option in chosen {
                    let id = HomeLayoutStore.categoryID(of: option.key)
                    if let listItems = byList[id], !listItems.isEmpty {
                        kindRows.append(HomeRow(id: option.key, title: option.name, kind: kind, categoryId: id,
                                                items: listItems))
                    }
                }
            } else if kind == .series {
                kindRows.append(HomeRow(id: "series", title: String(localized: "Series"), kind: kind, categoryId: nil,
                                        items: Array(items.prefix(rowLength))))
            } else {
                // No catch-all "Movies" row: the first lists say more.
                for category in store.movieCategories {
                    guard kindRows.count < 6 else { break }
                    if let listItems = byList[category.id], !listItems.isEmpty {
                        kindRows.append(HomeRow(id: "movie|" + category.id, title: category.name, kind: kind,
                                                categoryId: category.id, items: listItems))
                    }
                }
            }
            if let top = topTen(items, kind: kind) {
                kindRows.insert(top, at: min(1, kindRows.count))
            }
            rows += kindRows
        }
        return rows
    }

    /// The ten best-rated titles with artwork, if the provider rates enough of them.
    private static func topTen(_ items: [MediaItem], kind: MediaKind) -> HomeRow? {
        let rated = items.filter { ($0.rating ?? 0) > 0 && $0.posterURL != nil }
        guard rated.count >= 10 else { return nil }
        let top = rated.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }.prefix(10)
        let title = kind == .movie ? String(localized: "Top 10 Movies") : String(localized: "Top 10 Series")
        return HomeRow(id: "top10|\(kind.rawValue)", title: title, kind: kind, categoryId: nil, items: Array(top),
                       isRanked: true)
    }
}

// MARK: - Apple TV billboard

#if os(tvOS)
extension HomeView {
    /// The focused title's artwork across the top of the screen, its name and summary over it, the rows below.
    private var tvContent: some View {
        ZStack(alignment: .topLeading) {
            TVBillboardBackdrop(item: billboard)
            VStack(alignment: .leading, spacing: 0) {
                TVBillboardInfo(item: billboard)
                    .frame(maxWidth: .infinity, minHeight: 360, maxHeight: 360, alignment: .bottomLeading)
                    .padding(.horizontal, 80)
                    // Room between the summary and the first row's title.
                    .padding(.bottom, 40)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        shelves
                    }
                    .padding(.bottom, 60)
                }
                .scrollClipDisabled()
            }
        }
        .environment(\.lockupFocusAction, LockupFocusAction { focused = $0 })
        .task(id: focused?.id) {
            guard let focused else { return }
            // Settles before swapping the artwork: sliding along a row doesn't reload it for each poster.
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) { billboard = focused }
        }
    }
}

private struct TVBillboardBackdrop: View {
    let item: MediaItem?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Theme.background
                if let item {
                    RemoteImage(url: item.posterURL, maxPixelSize: 1000) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        GeneratedArtwork(title: item.name, kind: item.kind, showsTitle: false)
                    }
                    .frame(width: proxy.size.width * 0.68, height: proxy.size.height * 0.62)
                    .clipped()
                    // Faded on its own left and bottom edges: no seam where the artwork starts.
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0),
                                               .init(color: .black, location: 0.45)],
                                       startPoint: .leading, endPoint: .trailing)
                            .mask {
                                LinearGradient(stops: [.init(color: .black, location: 0.55),
                                                       .init(color: .clear, location: 1)],
                                               startPoint: .top, endPoint: .bottom)
                            }
                    }
                    .id(item.id)
                    .transition(.opacity)
                }
                // A little darker behind the text, so it reads over light artwork.
                LinearGradient(stops: [.init(color: Theme.background.opacity(0.7), location: 0.3),
                                       .init(color: .clear, location: 0.65)],
                               startPoint: .leading, endPoint: .trailing)
            }
        }
        .ignoresSafeArea()
    }
}

private struct TVBillboardInfo: View {
    @EnvironmentObject private var store: AppStore
    let item: MediaItem?

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 14) {
                Text(item.name)
                    .font(.title.weight(.bold))
                    .lineLimit(2)
                Text(item.metadataLine(category: store.categoryName(item.categoryId, kind: item.kind)))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                if let plot = item.plot, !plot.isEmpty {
                    Text(plot)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .id(item.id)
            .transition(.opacity)
        }
    }
}
#endif

// MARK: - See All

/// A Home row's whole list, as a grid of posters.
private struct HomeListGrid: View {
    @EnvironmentObject private var store: AppStore
    let row: HomeRow
    let onSelect: (MediaItem) -> Void
    @State private var items: [MediaItem] = []

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: Theme.posterWidth, maximum: Theme.posterWidth * 1.4),
                  spacing: LockupMetrics.gridSpacing)]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: LockupMetrics.gridRowSpacing) {
                ForEach(items) { item in
                    Button { onSelect(item) } label: {
                        PosterCard(item: item)
                    }
                    .lockupButtonStyle()
                    .favoriteContextMenu(item)
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(row.title)
        .task(id: row.id) {
            let all = store.items(for: row.kind)
            items = row.categoryId.map { id in all.filter { $0.belongs(to: id) } } ?? all
        }
    }
}

// MARK: - Banner

#if !os(tvOS)
/// The featured title across the top of Home: artwork, name, genre line, Play / My List / More Info.
struct HeroBanner: View {
    @EnvironmentObject private var store: AppStore
    let item: MediaItem
    let onPlay: () -> Void
    let onInfo: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            RemoteImage(url: item.posterURL, maxPixelSize: 1200) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                // The row poster, already in memory, until the sharper one arrives.
                RemoteImage(url: item.posterURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    GeneratedArtwork(title: item.name, kind: item.kind, showsTitle: false)
                }
            }
            .frame(height: Theme.heroHeight)
            .frame(maxWidth: .infinity)
            .clipped()

            // Dark at the top for the bar, into the page at the bottom.
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.25))
            LinearGradient(stops: [.init(color: .clear, location: 0.35),
                                   .init(color: Theme.background.opacity(0.85), location: 0.78),
                                   .init(color: Theme.background, location: 1)],
                           startPoint: .top, endPoint: .bottom)

            VStack(spacing: 12) {
                Text(item.name)
                    .font(.system(.largeTitle, design: .default).weight(.heavy))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.5), radius: 8)
                Text(item.metadataLine(category: store.categoryName(item.categoryId, kind: item.kind)))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .frame(minWidth: 110)
                            .padding(.vertical, 9)
                    }
                    .primaryActionStyle()
                    myListButton
                    Button(action: onInfo) {
                        Label("More Info", systemImage: "info.circle")
                            .labelStyle(.iconOnly)
                            .font(.headline)
                            .padding(.vertical, 9)
                    }
                    .secondaryActionStyle()
                    .accessibilityLabel("More Info")
                }
                .sensoryFeedback(.selection, trigger: store.isFavorite(item))
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(height: Theme.heroHeight)
        .contentShape(Rectangle())
        .onTapGesture(perform: onInfo)
    }

    private var myListButton: some View {
        let isFavorite = store.isFavorite(item)
        return Button { store.toggleFavorite(item) } label: {
            Label("My List", systemImage: isFavorite ? "checkmark" : "plus")
                .font(.headline)
                .contentTransition(.symbolEffect(.replace))
                .padding(.vertical, 9)
        }
        .secondaryActionStyle()
        .accessibilityLabel(isFavorite ? "Remove from My List" : "Add to My List")
    }
}
#endif

extension MediaItem {
    /// "2025 · ★ 7.3 · Drama": Netflix's line of facts under a title.
    func metadataLine(category: String) -> String {
        var parts: [String] = []
        if let year, !year.isEmpty { parts.append(year) }
        if let rating, rating > 0 { parts.append("★ " + String(format: "%.1f", rating)) }
        if !category.isEmpty { parts.append(category) }
        return parts.joined(separator: " · ")
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
