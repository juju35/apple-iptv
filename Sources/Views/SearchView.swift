#if os(tvOS)
import SwiftUI

/// Apple TV's Search tab: the system search screen (keyboard and dictation on top), results below as
/// shelves of channels, movies and series. The other tabs don't search on Apple TV.
struct SearchView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = Demo.isOn && Demo.screen == .search ? "the" : ""
    @State private var selectedItem: MediaItem?
    /// Computed once the typing pauses, not on every render (each focus move re-renders on Apple TV).
    @State private var results: [MediaKind: [MediaItem]] = [:]
    @State private var resultsQuery = ""

    private struct Inputs: Equatable {
        let query: String
        let counts: [Int]
    }

    private var inputs: Inputs {
        Inputs(query: query, counts: [MediaKind.live, .movie, .series].map { store.items(for: $0).count })
    }

    private func updateResults() async {
        guard !query.isEmpty else { results = [:]; resultsQuery = ""; return }
        // Debounce: dictation and the on-screen keyboard send one character at a time.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        var found: [MediaKind: [MediaItem]] = [:]
        for kind in [MediaKind.live, .movie, .series] {
            found[kind] = MediaSearch.results(store.items(for: kind), matching: query, limit: 40)
        }
        results = found
        resultsQuery = query
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    let shelves: [(String, [MediaItem])] = [
                        (String(localized: "Channels"), results[.live] ?? []),
                        (String(localized: "Movies"), results[.movie] ?? []),
                        (String(localized: "Series"), results[.series] ?? []),
                    ]
                    ForEach(shelves, id: \.0) { title, items in
                        if !items.isEmpty {
                            MediaRow(title: title, items: items) { selectedItem = $0 }
                        }
                    }
                    // Only once this query was searched: no "No Results" flash while typing.
                    if !query.isEmpty && resultsQuery == query && shelves.allSatisfy({ $0.1.isEmpty }) {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .searchable(text: $query, prompt: "Channels, movies and series")
            .task(id: inputs) { await updateResults() }
            .detailPresentation(item: $selectedItem) { item in
                MediaDetailView(item: item)
            }
        }
    }
}
#endif
