import SwiftUI

/// Toggles for the tags found in the catalog; switched-off tags are hidden everywhere.
struct TagFilterView: View {
    let title: String
    let options: [ContentTags.Option]
    @Binding var hidden: Set<String>

    var body: some View {
        List {
            if options.isEmpty {
                Text("No tags found in this provider's names.")
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Section {
                    Button("Show all") { hidden.subtract(options.map(\.tag)) }
                    Button("Hide all") { hidden.formUnion(options.map(\.tag)) }
                }
                Section {
                    ForEach(options) { option in
                        Toggle(isOn: isShown(option.tag)) {
                            HStack {
                                Text(option.tag)
                                Spacer()
                                Text("\(option.count)").foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
    }

    private func isShown(_ tag: String) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(tag) },
            set: { shown in
                if shown { hidden.remove(tag) } else { hidden.insert(tag) }
            }
        )
    }
}

/// Text to remove from list names ("FR |", "VIP"…), with a before / after preview of the lists it changes.
struct ListNameCleanupView: View {
    @EnvironmentObject private var store: AppStore
    @State private var newText = ""
    @FocusState private var isEditing: Bool

    /// Every list name of the provider, as sent, to pick from.
    private var allListNames: [String] {
        let names = [MediaKind.live, .movie, .series].flatMap { store.listOptions[$0] ?? [] }.map(\.originalName)
        return Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Lists whose shown name differs from the provider's, all kinds together.
    private var changedLists: [CategoryListOption] {
        [MediaKind.live, .movie, .series].flatMap { store.listOptions[$0] ?? [] }
            .filter { $0.name != $0.originalName }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Text to remove, e.g. FR |", text: $newText)
                        .autocorrectionDisabledIfSupported()
                        .focused($isEditing)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("""
                    Removed from every list name shown, ignoring case. Separators left at the start or end \
                    (|, -, :) go too. Language detection still reads the original names. \
                    Pick a list below to start from its name.
                    """)
            }

            if !store.listNameRemovals.isEmpty {
                Section("Removed text") {
                    ForEach(store.listNameRemovals, id: \.self) { text in
                        HStack {
                            Text("\"\(text)\"").font(.body.monospaced())
                            Spacer()
                            Button(role: .destructive) {
                                store.listNameRemovals.removeAll { $0 == text }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Stop removing \(text)")
                        }
                    }
                }
            }

            if !changedLists.isEmpty {
                Section("Preview") {
                    ForEach(changedLists.prefix(30)) { option in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.name)
                            Text(option.originalName)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .strikethrough()
                        }
                    }
                }
            }

            if !allListNames.isEmpty {
                Section("Lists") {
                    ForEach(allListNames, id: \.self) { name in
                        Button {
                            // Start from the whole name; the user trims it down to the part to remove.
                            newText = name
                            isEditing = true
                        } label: {
                            HStack {
                                Text(name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "text.cursor").foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .accessibilityHint("Copies the name into the text field")
                    }
                }
            }
        }
        .navigationTitle("Clean up list names")
    }

    private func add() {
        let text = newText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !store.listNameRemovals.contains(text) else { return }
        store.listNameRemovals.append(text)
        newText = ""
    }
}

private extension View {
    @ViewBuilder
    func autocorrectionDisabledIfSupported() -> some View {
        #if os(macOS)
        self
        #else
        autocorrectionDisabled().textInputAutocapitalization(.never)
        #endif
    }
}

/// Toggles for the selected provider's lists of one kind, with a search field (providers have hundreds).
struct ListFilterView: View {
    let title: String
    let options: [CategoryListOption]
    @Binding var hidden: Set<String>
    @State private var search = ""

    private var filtered: [CategoryListOption] {
        search.isEmpty ? options : options.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            if options.isEmpty {
                Text("No lists for this provider.")
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Section {
                    Button(search.isEmpty ? "Show all" : "Show these") { hidden.subtract(filtered.map(\.key)) }
                    Button(search.isEmpty ? "Hide all" : "Hide these") { hidden.formUnion(filtered.map(\.key)) }
                }
                Section {
                    ForEach(filtered) { option in
                        Toggle(isOn: isShown(option.key)) {
                            HStack {
                                Text(option.name)
                                Spacer()
                                Text("\(option.count)").foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .modifier(BrowseSearch(text: $search))
    }

    private func isShown(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(key) },
            set: { shown in
                if shown { hidden.remove(key) } else { hidden.insert(key) }
            }
        )
    }
}
