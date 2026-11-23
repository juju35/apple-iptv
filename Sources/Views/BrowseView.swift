import SwiftUI

/// Grid browser for a media kind, with category filter and search.
struct BrowseView: View {
    @EnvironmentObject private var store: AppStore
    let kind: MediaKind
    let title: String

    @State private var selectedCategory: String?
    @State private var search = ""
    @State private var selectedItem: MediaItem?

    /// Recomputed only when their inputs change: every store update re-renders this view, and filtering
    /// thousands of movies on each one weighed on scrolling.
    @State private var filtered: [MediaItem] = []
    @State private var categoryOptions: [ChipOption<String?>] = []

    private struct Inputs: Hashable {
        let category: String?
        let count: Int
        let firstID: String?
        let lastID: String?
        let categoryCount: Int
    }

    private var inputs: Inputs {
        let items = store.items(for: kind)
        return Inputs(category: selectedCategory, count: items.count, firstID: items.first?.id,
                      lastID: items.last?.id, categoryCount: store.categories(for: kind).count)
    }

    private func categoryItems() -> [MediaItem] {
        let items = store.items(for: kind)
        guard let selectedCategory else { return items }
        return items.filter { $0.belongs(to: selectedCategory) }
    }

    /// "All" then the categories that still have items once filters apply.
    private func computeCategoryOptions() -> [ChipOption<String?>] {
        let used = Set(store.items(for: kind).flatMap(\.categoryIds))
        return [ChipOption(id: nil, title: String(localized: "All"))]
            + store.categories(for: kind).filter { used.contains($0.id) }
                .map { ChipOption(id: Optional($0.id), title: $0.name) }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: Theme.posterWidth, maximum: Theme.posterWidth * 1.4),
                  spacing: LockupMetrics.gridSpacing)]
    }

    private func cell(_ item: MediaItem) -> some View {
        Button { selectedItem = item } label: {
            PosterCard(item: item)
        }
        .lockupButtonStyle()
        .favoriteContextMenu(item)
    }

    #if !os(tvOS)
    private var posterGrid: some View {
        LazyVGrid(columns: columns, spacing: LockupMetrics.gridRowSpacing) {
            ForEach(filtered) { cell($0) }
        }
    }
    #endif

    /// Started movies / series and favorites first, unless the user is narrowing the list down.
    private var header: some View {
        VStack(alignment: .leading, spacing: 22) {
            CategoryChips(options: categoryOptions, selection: $selectedCategory)
            if search.isEmpty && selectedCategory == nil {
                ContinueWatchingRow(entries: store.continueWatching(kind)) { selectedItem = $0 }
                let favorites = store.favorites(kind)
                if !favorites.isEmpty {
                    MediaRow(title: String(localized: "My List"), items: favorites) { selectedItem = $0 }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        #if os(tvOS)
        // A UIKit collection view: SwiftUI grids crawled through thousands of posters on Apple TV.
        let isNarrowed = !search.isEmpty || selectedCategory != nil
        TVPosterGrid(items: filtered, continueWatching: isNarrowed ? [] : store.continueWatching(kind),
                     favorites: isNarrowed ? [] : store.favorites(kind), onSelect: { selectedItem = $0 },
                     chips: { CategoryChips(options: categoryOptions, selection: $selectedCategory) })
        .ignoresSafeArea(edges: .bottom)
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                posterGrid
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        #endif
    }

    var body: some View {
        NavigationStack {
            content
            .background(Theme.background.ignoresSafeArea())
            .tabScreenTitle(title)
            .providerToolbar()
            .modifier(BrowseSearch(text: $search))
            .detailPresentation(item: $selectedItem) { item in
                MediaDetailView(item: item)
            }
            // The search isn't an input: options and the unsearched list don't change while typing.
            .onChange(of: inputs, initial: true) {
                if search.isEmpty { filtered = categoryItems() }
                categoryOptions = computeCategoryOptions()
            }
            .onChange(of: search) {
                if search.isEmpty { filtered = categoryItems() }
            }
            .task(id: [AnyHashable(inputs), AnyHashable(search)]) {
                guard !search.isEmpty else { return }
                if let found = await SearchDebounce.results(categoryItems(), matching: search) { filtered = found }
            }
            .task(id: filtered.count) {
                // Screenshot mode: `-demoScreen detail` opens the first series.
                if Demo.isOn, Demo.screen == .detail, kind == .series, selectedItem == nil {
                    selectedItem = filtered.first
                }
            }
        }
    }
}

/// Searches once the typing pauses, off the main thread: searching the whole catalog at every
/// character made typing lag. Nil when a newer search replaced this one (its task was cancelled).
enum SearchDebounce {
    static let delay = Duration.milliseconds(300)

    static func results(_ items: [MediaItem], matching query: String, limit: Int? = nil) async -> [MediaItem]? {
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return nil }
        let found = await MediaSearch.results(items, matching: query, limit: limit)
        return Task.isCancelled ? nil : found
    }
}

/// System search everywhere except for the iOS app running on a Mac ("Designed for iPad"),
/// where activating `UISearchController` inside the tab view crashes in UIKit
/// ("Accessing the focus system through UIScreen is no longer supported").
/// That case gets a plain text field pinned above the content instead.
struct BrowseSearch: ViewModifier {
    @Binding var text: String

    func body(content: Content) -> some View {
        #if os(iOS)
        if ProcessInfo.processInfo.isiOSAppOnMac {
            content.safeAreaInset(edge: .top) { InlineSearchField(text: $text) }
        } else {
            systemSearch(content)
        }
        #elseif os(tvOS)
        // Apple TV searches from its own tab (SearchView): no keyboard over every list.
        content
        #else
        systemSearch(content)
        #endif
    }

    private func systemSearch(_ content: Content) -> some View {
        content
            .searchable(text: $text)
            .modifier(ClearingSearchDropsFocus(text: $text))
    }
}

#if os(iOS)
/// Search field that doesn't go through `UISearchController`. Its clear button also drops
/// the focus, like `ClearingSearchDropsFocus` does for the system field.
private struct InlineSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
            TextField("Search", text: $text)
                .focused($isFocused)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Theme.background)
    }
}
#endif

/// Unfocuses the search field when its clear (×) button empties it, so the keyboard
/// doesn't come back. Backspacing the last character keeps the focus: only a jump from
/// several characters to none counts as clearing. Needs `searchFocused` (iOS 18, macOS 15; not on tvOS).
private struct ClearingSearchDropsFocus: ViewModifier {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        #if os(tvOS)
        // No searchFocused on tvOS: the search screen has its own keyboard and dismisses it itself.
        content
        #else
        if #available(iOS 18, macOS 15, *) {
            content
                .searchFocused($isFocused)
                .onChange(of: text) { oldValue, newValue in
                    if newValue.isEmpty && oldValue.count > 1 {
                        isFocused = false
                    }
                }
        } else {
            content
        }
        #endif
    }
}
