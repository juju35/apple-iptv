import SwiftUI

@main
struct IPTVApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task { await store.reload() }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if store.providers.isEmpty {
            OnboardingView()
        } else {
            MainTabView()
        }
    }
}

enum MainTab: Hashable {
    case home, live, movies, series, settings
}

struct MainTabView: View {
    // Only read through its binding, which the analyzer misses since @State became a macro.
    // swiftlint:disable:next unused_declaration
    @State private var tab: MainTab = Demo.isOn ? Demo.screen.tab : .home
    #if os(macOS)
    /// Player shown over the whole window: macOS sheets can't fill it.
    @State private var windowPlayback: PlaybackRequest?
    /// Title bar and tabs over the player: hidden during playback, shown with the player controls.
    @State private var playerChromeVisible = true
    #endif

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(MainTab.home)
            BrowseView(kind: .live, title: "Live TV")
                .tabItem { Label("Live TV", systemImage: "tv") }
                .tag(MainTab.live)
            BrowseView(kind: .movie, title: "Movies")
                .tabItem { Label("Movies", systemImage: "film") }
                .tag(MainTab.movies)
            BrowseView(kind: .series, title: "Series")
                .tabItem { Label("Series", systemImage: "play.rectangle.on.rectangle") }
                .tag(MainTab.series)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
        .tint(Theme.accent)
        .background(Theme.background)
        #if os(macOS)
        .environment(\.presentPlayer) { windowPlayback = $0 }
        .overlay {
            if let request = windowPlayback {
                PlayerView(request: request)
                    .id(request.id)
                    .environment(\.closePlayer) {
                        windowPlayback = nil
                        playerChromeVisible = true
                    }
                    .environment(\.playerChromeVisible, $playerChromeVisible)
                    .ignoresSafeArea()
            }
        }
        .toolbar(windowPlayback != nil && !playerChromeVisible ? .hidden : .automatic,
                 for: .windowToolbar)
        #endif
        #if os(iOS)
        // Screenshot mode: `-demoScreen player` shows the player's fold layout over the tabs.
        .overlay {
            if Demo.isOn && Demo.screen == .player {
                if #available(iOS 27.1, *) { DemoPlayerView() }
            }
        }
        #endif
    }
}

extension Demo.Screen {
    /// The tab a demo screen opens on.
    var tab: MainTab {
        switch self {
        case .home, .player: return .home
        case .live: return .live
        case .movies: return .movies
        case .series, .detail: return .series
        case .settings: return .settings
        }
    }
}
