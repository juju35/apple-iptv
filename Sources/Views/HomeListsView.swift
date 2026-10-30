import SwiftUI

/// Settings › Home lists: which movie and series lists appear as rows on Home.
struct HomeListsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var layout: HomeLayoutStore

    var body: some View {
        List {
            section(String(localized: "Movies"), kind: .movie)
            section(String(localized: "Series"), kind: .series)
        }
        .navigationTitle("Home lists")
    }

    @ViewBuilder
    private func section(_ title: String, kind: MediaKind) -> some View {
        let options = (store.listOptions[kind] ?? []).filter { $0.count > 0 }
        if !options.isEmpty {
            Section {
                ForEach(options) { option in
                    Toggle(isOn: Binding(get: { layout.isShown(option.key) },
                                         set: { layout.setShown(option.key, $0) })) {
                        HStack {
                            Text(option.name)
                            Spacer()
                            Text("\(option.count)").foregroundStyle(Theme.rowSecondary)
                        }
                    }
                }
            } header: {
                Text(title)
            } footer: {
                Text("With no list chosen, Home shows its default rows.")
            }
        }
    }
}
