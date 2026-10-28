import SwiftUI

/// Grid browser for a media kind, with category filter and search.
struct BrowseView: View {
    @EnvironmentObject private var store: AppStore
    let kind: MediaKind
    let title: String

    @State private var selectedCategory: String?
    @State private var search = ""
    @State private var selectedItem: MediaItem?

    private var filtered: [MediaItem] {
        var items = store.items(for: kind)
        if let selectedCategory {
            items = items.filter { $0.categoryId == selectedCategory }
        }
        if !search.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(search) }
        }
        return items
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: Theme.posterWidth, maximum: Theme.posterWidth * 1.4), spacing: 16)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Started movies / series first, unless the user is narrowing the list down.
                    if search.isEmpty && selectedCategory == nil {
                        ContinueWatchingRow(entries: store.continueWatching(kind)) { selectedItem = $0 }
                    }
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(filtered) { item in
                            Button { selectedItem = item } label: {
                                PosterCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .modifier(BrowseSearch(text: $search))
            .toolbar {
                Menu {
                    Button("All categories") { selectedCategory = nil }
                    ForEach(store.categories(for: kind)) { category in
                        Button(category.name) { selectedCategory = category.id }
                    }
                } label: {
                    Label(
                        selectedCategory.map { store.categoryName($0, kind: kind) } ?? "Categories",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }
            }
            .sheet(item: $selectedItem) { item in
                MediaDetailView(item: item)
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
private struct BrowseSearch: ViewModifier {
    @Binding var text: String

    func body(content: Content) -> some View {
        #if os(iOS)
        if ProcessInfo.processInfo.isiOSAppOnMac {
            content.safeAreaInset(edge: .top) { InlineSearchField(text: $text) }
        } else {
            systemSearch(content)
        }
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
