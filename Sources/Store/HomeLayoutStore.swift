import Foundation

/// The movie and series lists shown as rows on Home, chosen in Settings and synced through iCloud.
/// Keys are `CategoryListOption.key`s (provider, kind and list); a provider with none chosen gets
/// the default rows.
@MainActor
final class HomeLayoutStore: ObservableObject {
    static let key = "iptv.homeLists"

    @Published var listKeys: [String] {
        didSet { if !Demo.isOn { sync.save(listKeys) } }
    }

    private let sync = CloudStringListStore(key: HomeLayoutStore.key)

    init() {
        listKeys = Demo.isOn ? [] : sync.load()
        sync.onExternalChange = { [weak self] remote in
            Task { @MainActor in
                guard let self, self.listKeys != remote else { return }
                self.listKeys = remote
            }
        }
    }

    func isShown(_ key: String) -> Bool { listKeys.contains(key) }

    func setShown(_ key: String, _ shown: Bool) {
        if shown, !listKeys.contains(key) {
            listKeys.append(key)
        } else if !shown {
            listKeys.removeAll { $0 == key }
        }
    }

    /// The chosen lists among `options` (the selected provider's), in the lists' own order;
    /// nil when none of them is chosen, for the default rows.
    func chosen(among options: [CategoryListOption]) -> [CategoryListOption]? {
        let keys = Set(listKeys)
        let chosen = options.filter { keys.contains($0.key) }
        return chosen.isEmpty ? nil : chosen
    }

    /// The list id inside a `CategoryListOption.key` (`<provider>|<kind>|<list>`).
    static func categoryID(of key: String) -> String {
        String(key.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).last ?? "")
    }
}
