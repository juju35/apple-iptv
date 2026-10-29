#if os(tvOS)
import SwiftUI

/// Apple TV's Search tab: the system search screen (keyboard and dictation on top), results below as
/// shelves of channels, movies and series. The other tabs don't search on Apple TV.
struct SearchView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = Demo.isOn && Demo.screen == .search ? "the" : ""
    @State private var selectedItem: MediaItem?

    private func results(_ kind: MediaKind) -> [MediaItem] {
        guard !query.isEmpty else { return [] }
        return Array(store.items(for: kind).filter { $0.name.localizedCaseInsensitiveContains(query) }.prefix(40))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    let shelves: [(String, [MediaItem])] = [
                        (String(localized: "Channels"), results(.live)), (String(localized: "Movies"), results(.movie)),
                        (String(localized: "Series"), results(.series)),
                    ]
                    ForEach(shelves, id: \.0) { title, items in
                        if !items.isEmpty {
                            MediaRow(title: title, items: items) { selectedItem = $0 }
                        }
                    }
                    if !query.isEmpty && shelves.allSatisfy({ $0.1.isEmpty }) {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .searchable(text: $query, prompt: "Channels, movies and series")
            .detailPresentation(item: $selectedItem) { item in
                MediaDetailView(item: item)
            }
        }
    }
}
#endif
