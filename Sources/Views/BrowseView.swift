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
        let search: String
        let count: Int
        let firstID: String?
        let lastID: String?
        let categoryCount: Int
    }

    private var inputs: Inputs {
        let items = store.items(for: kind)
        return Inputs(category: selectedCategory, search: search, count: items.count, firstID: items.first?.id,
                      lastID: items.last?.id, categoryCount: store.categories(for: kind).count)
    }

    private func computeFiltered() -> [MediaItem] {
        var items = store.items(for: kind)
        if let selectedCategory {
            items = items.filter { $0.belongs(to: selectedCategory) }
        }
        if !search.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(search) }
        }
        return items
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

    #if os(tvOS)
    /// Apple TV: rows of posters in a lazy stack, their artwork loaded 20 rows ahead. `LazyVGrid` lays out and tracks focus for the whole
    /// catalogue (thousands of movies) and made scrolling crawl; a lazy stack of fixed rows doesn't.
    @State private var gridWidth: CGFloat = 1700
    /// Rows whose artwork is loaded ahead of the focus.
    private static let prefetchRows = 20

    private struct PosterRow: Identifiable {
        let id: String
        let items: [MediaItem]
    }

    private var posterGrid: some View {
        let spacing = LockupMetrics.gridSpacing
        let perRow = max(1, Int((gridWidth + spacing) / (Theme.posterWidth + spacing)))
        let rows = stride(from: 0, to: filtered.count, by: perRow).map { start in
            let slice = Array(filtered[start..<min(start + perRow, filtered.count)])
            return PosterRow(id: slice[0].id, items: slice)
        }
        return LazyVStack(alignment: .leading, spacing: LockupMetrics.gridRowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(row.items) { cell($0) }
                }
                .onAppear {
                    // The artwork of the next 20 rows, so it's there when the focus gets to them.
                    let ahead = rows[min(index + 1, rows.count)..<min(index + 1 + Self.prefetchRows, rows.count)]
                    ImageLoader.shared.prefetch(ahead.flatMap(\.items).compactMap(\.posterURL))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { gridWidth = $0 }
    }
    #else
    private var posterGrid: some View {
        LazyVGrid(columns: columns, spacing: LockupMetrics.gridRowSpacing) {
            ForEach(filtered) { cell($0) }
        }
    }
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Started movies / series and favorites first, unless the user is narrowing the list down.
                    CategoryChips(options: categoryOptions, selection: $selectedCategory)
                    if search.isEmpty && selectedCategory == nil {
                        ContinueWatchingRow(entries: store.continueWatching(kind)) { selectedItem = $0 }
                        let favorites = store.favorites(kind)
                        if !favorites.isEmpty {
                            MediaRow(title: String(localized: "Favorites"), items: favorites) { selectedItem = $0 }
                        }
                    }
                    posterGrid
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Theme.background.ignoresSafeArea())
            .tabScreenTitle(title)
            .providerToolbar()
            .modifier(BrowseSearch(text: $search))
            .detailPresentation(item: $selectedItem) { item in
                MediaDetailView(item: item)
            }
            .onChange(of: inputs, initial: true) {
                filtered = computeFiltered()
                categoryOptions = computeCategoryOptions()
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
