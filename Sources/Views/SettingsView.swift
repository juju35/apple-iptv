import SwiftUI

/// Provider management: add/edit Xtream or Stalker accounts, pick the active one.
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editingProvider: Provider?
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                Section("Providers") {
                    ForEach(store.providers) { provider in
                        Button {
                            store.selectedProviderID = provider.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider.name).font(.headline)
                                    Text(provider.kind.label)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                    if let info = store.accountInfo[provider.id] {
                                        ExpiryLabel(info: info)
                                    }
                                }
                                Spacer()
                                if provider.id == store.selectedProvider?.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActionsCompat {
                            Button("Edit") { editingProvider = provider }
                            Button("Delete", role: .destructive) { store.removeProvider(provider) }
                        }
                    }
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add provider", systemImage: "plus.circle.fill")
                    }
                }

                Section {
                    NavigationLink {
                        TagFilterView(title: "Languages", options: store.languageOptions,
                                      hidden: $store.hiddenLanguages)
                    } label: {
                        filterRow("Languages", options: store.languageOptions, hidden: store.hiddenLanguages)
                    }
                    NavigationLink {
                        TagFilterView(title: "Live TV quality", options: store.qualityOptions,
                                      hidden: $store.hiddenQualities)
                    } label: {
                        filterRow("Live TV quality", options: store.qualityOptions, hidden: store.hiddenQualities)
                    }
                    listFilterLink("Live TV lists", kind: .live)
                    listFilterLink("Movie lists", kind: .movie)
                    listFilterLink("Series lists", kind: .series)
                    NavigationLink {
                        ListNameCleanupView()
                    } label: {
                        HStack {
                            Text("Clean up list names")
                            Spacer()
                            Text(store.listNameRemovals.isEmpty ? "Off" : "\(store.listNameRemovals.count)")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                } header: {
                    Text("Filters")
                } footer: {
                    Text("Tags are read from category and channel names; untagged content is always shown. "
                         + "Lists are those of the selected provider.")
                }

                Section {
                    Picker("Keep lists for", selection: $store.cacheLifetime) {
                        ForEach(CatalogCache.lifetimes, id: \.seconds) { option in
                            Text(option.label).tag(option.seconds)
                        }
                    }
                    Button("Refresh content") { Task { await store.reload(force: true) } }
                } header: {
                    Text("Cache")
                } footer: {
                    if let updatedAt = store.catalogUpdatedAt {
                        Text("Lists updated \(updatedAt, format: .relative(presentation: .named)).")
                    } else {
                        Text("Lists are kept on this device so the app opens without waiting for the provider.")
                    }
                }

                ProgrammeGuideSection()
            }
            .navigationTitle("Settings")
            .task { await store.refreshAccountInfo() }
            .sheet(isPresented: $showingAdd) {
                ProviderFormView(provider: nil)
            }
            .sheet(item: $editingProvider) { provider in
                ProviderFormView(provider: provider)
            }
        }
    }

    private func listFilterLink(_ title: String, kind: MediaKind) -> some View {
        let options = store.listOptions[kind] ?? []
        let shown = options.filter { !store.hiddenCategories.contains($0.key) }.count
        return NavigationLink {
            ListFilterView(title: title, options: options, hidden: $store.hiddenCategories)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(shown == options.count ? "All" : "\(shown) of \(options.count)")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func filterRow(_ title: String, options: [ContentTags.Option], hidden: Set<String>) -> some View {
        let shown = options.filter { !hidden.contains($0.tag) }.count
        return HStack {
            Text(title)
            Spacer()
            Text(shown == options.count ? "All" : "\(shown) of \(options.count)")
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// "Expires 31 Dec 2026", orange within 14 days, red once expired.
struct ExpiryLabel: View {
    let info: AccountInfo

    var body: some View {
        if info.isUnlimited {
            Label("No expiry", systemImage: "infinity").font(.caption).foregroundStyle(Theme.textSecondary)
        } else if let date = info.expiresAt {
            let remaining = date.timeIntervalSinceNow
            Label(remaining < 0 ? "Expired \(date.formatted(date: .abbreviated, time: .omitted))"
                                : "Expires \(date.formatted(date: .abbreviated, time: .omitted))",
                  systemImage: remaining < 0 ? "exclamationmark.circle.fill" : "calendar")
                .font(.caption)
                .foregroundStyle(remaining < 0 ? .red : remaining < 14 * 24 * 3600 ? .orange : Theme.textSecondary)
        }
    }
}

struct ProviderFormView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let provider: Provider?

    @State private var name = ""
    @State private var kind: Provider.Kind = .xtream
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var macAddress = ""
    @State private var testResult: String?
    @State private var testing = false

    private var isValid: Bool {
        guard !name.isEmpty, URL(string: serverURL) != nil else { return false }
        switch kind {
        case .xtream: return !username.isEmpty && !password.isEmpty
        case .stalker: return Self.isValidMAC(macAddress)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $kind) {
                        ForEach(Provider.Kind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    TextField("Server URL (http://host:port)", text: $serverURL)
                        .textContentTypeCompat()
                }

                switch kind {
                case .xtream:
                    Section("Xtream credentials") {
                        TextField("Username", text: $username)
                        SecureField("Password", text: $password)
                    }
                case .stalker:
                    Section("Stalker portal") {
                        TextField("MAC address (00:1A:79:XX:XX:XX)", text: $macAddress)
                            .onChange(of: macAddress) { _, newValue in
                                macAddress = Self.formatMAC(newValue)
                            }
                        Text("Portal URL usually ends with /stalker_portal or /c")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Section {
                    Button(testing ? "Testing…" : "Test connection") { testConnection() }
                        .disabled(!isValid || testing)
                    if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testResult.hasPrefix("OK") ? .green : .orange)
                    }
                }
            }
            .navigationTitle(provider == nil ? "Add provider" : "Edit provider")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .onAppear(perform: populate)
        }
        .preferredColorScheme(.dark)
    }

    private func populate() {
        guard let provider else { return }
        name = provider.name
        kind = provider.kind
        serverURL = provider.serverURL
        username = provider.username
        password = provider.password
        macAddress = provider.macAddress
    }

    private func currentProvider() -> Provider {
        var p = provider ?? Provider(name: name, kind: kind, serverURL: serverURL)
        p.name = name
        p.kind = kind
        p.serverURL = serverURL
        p.username = username
        p.password = password
        p.macAddress = macAddress
        return p
    }

    private func save() {
        let p = currentProvider()
        if provider == nil {
            store.addProvider(p)
        } else {
            store.updateProvider(p)
        }
        dismiss()
    }

    private func testConnection() {
        testing = true
        testResult = nil
        let client = IPTVClientFactory.client(for: currentProvider())
        Task {
            do {
                try await client.authenticate()
                testResult = "OK — authenticated successfully"
            } catch {
                testResult = error.localizedDescription
            }
            testing = false
        }
    }

    // MARK: - MAC helpers

    static func isValidMAC(_ mac: String) -> Bool {
        let pattern = "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$"
        return mac.range(of: pattern, options: .regularExpression) != nil
    }

    static func formatMAC(_ raw: String) -> String {
        let hex = raw.uppercased().filter { "0123456789ABCDEF".contains($0) }.prefix(12)
        var result = ""
        for (index, char) in hex.enumerated() {
            if index > 0 && index % 2 == 0 { result.append(":") }
            result.append(char)
        }
        return result
    }
}

struct OnboardingView: View {
    @State private var showingAdd = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
            Text("AppleIPTV")
                .font(.largeTitle.weight(.bold))
            Text("Add an Xtream Codes or Stalker (MAC) provider to start watching.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
            Button {
                showingAdd = true
            } label: {
                Label("Add provider", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 20).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showingAdd) {
            ProviderFormView(provider: nil)
        }
    }
}

// MARK: - Platform shims

extension View {
    @ViewBuilder
    func swipeActionsCompat<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        #if os(iOS)
        self.swipeActions(edge: .trailing, content: content)
        #else
        self.contextMenu(menuItems: content)
        #endif
    }

    @ViewBuilder
    func textContentTypeCompat() -> some View {
        #if os(iOS) || os(tvOS)
        self.textContentType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        #else
        self.autocorrectionDisabled()
        #endif
    }
}

/// How long the provider's programme guide is kept, with its state and a refresh button.
private struct ProgrammeGuideSection: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var guide: EPGStore

    var body: some View {
        Section {
            Picker("Keep the guide for", selection: $guide.lifetime) {
                ForEach(EPGStore.lifetimes, id: \.seconds) { option in
                    Text(option.label).tag(option.seconds)
                }
            }
            Button {
                Task { await guide.refresh(using: store, force: true) }
            } label: {
                HStack {
                    Text("Refresh the guide")
                    if guide.isLoading {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(guide.isLoading || guide.lifetime == 0)
        } header: {
            Text("Programme guide")
        } footer: {
            if let error = guide.lastError {
                Text("The guide couldn't be downloaded: \(error)")
            } else if let updatedAt = guide.updatedAt {
                Text("Guide for \(guide.guide.count) channels, updated "
                     + "\(updatedAt.formatted(.relative(presentation: .named))).")
            } else if guide.lifetime == 0 {
                Text("Off: channels only show the short guide the provider sends for each one.")
            } else {
                Text("The provider's whole guide is downloaded and kept on this device; "
                     + "without one, channels show their short guide.")
            }
        }
    }
}
