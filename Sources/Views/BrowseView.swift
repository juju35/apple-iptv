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
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(filtered) { item in
                        Button { selectedItem = item } label: {
                            PosterCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .searchable(text: $search)
            .modifier(ClearingSearchDropsFocus(text: $search))
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
