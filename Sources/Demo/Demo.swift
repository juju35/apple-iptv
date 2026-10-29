import Foundation

/// Screenshot mode, for scripts/screenshots.sh only: launched with `-demo YES`, the app shows made-up channels,
/// films and series instead of a provider's (nothing is fetched, nothing is saved to iCloud), and
/// `-demoScreen home|live|movies|series|detail|settings|player|search` opens that screen (search: Apple TV, with
/// a query typed in).
enum Demo {
    enum Screen: String {
        case home, live, movies, series, detail, settings, player, search
    }

    static let isOn = UserDefaults.standard.bool(forKey: "demo")
    static let screen = UserDefaults.standard.string(forKey: "demoScreen").flatMap(Screen.init(rawValue:)) ?? .home

    static let provider = Provider(
        id: UUID(uuidString: "6D3B1C2A-0000-4000-8000-0000000000DE") ?? UUID(),
        name: "Demo TV",
        kind: .xtream,
        serverURL: "http://demo.invalid",
        username: "demo",
        password: "demo"
    )
}
