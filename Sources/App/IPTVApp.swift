import SwiftUI

@main
struct IPTVApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var epg = EPGStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(epg)
                .preferredColorScheme(.dark)
                .task { await store.reload() }
                // Once the provider's channels are known (cached or fresh), load its guide.
                .task(id: store.catalogUpdatedAt) { await epg.refresh(using: store) }
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
    #if os(tvOS)
    case search
    #endif
}

struct MainTabView: View {
    @State private var tab: MainTab = Demo.isOn ? Demo.screen.tab : .home
    #if os(macOS)
    /// Player shown over the whole window: macOS sheets can't fill it.
    @State private var windowPlayback: PlaybackRequest?
    #endif

    var body: some View {
        TabView(selection: $tab) {
            #if os(tvOS)
            // First, as in Apple's own apps: the only place to search on Apple TV.
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(MainTab.search)
            #endif
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(MainTab.home)
            LiveTVView()
                .tabItem { Label("Live TV", systemImage: "tv") }
                .tag(MainTab.live)
            BrowseView(kind: .movie, title: String(localized: "Movies"))
                .tabItem { Label("Movies", systemImage: "film") }
                .tag(MainTab.movies)
            BrowseView(kind: .series, title: String(localized: "Series"))
                .tabItem { Label("Series", systemImage: "play.rectangle.on.rectangle") }
                .tag(MainTab.series)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
        .brandTint()
        .background(Theme.background)
        .environment(\.showSettings, ShowSettingsAction { tab = .settings })
        #if os(macOS)
        .environment(\.presentPlayer, PresentPlayerAction { windowPlayback = $0 })
        .overlay {
            if let request = windowPlayback {
                PlayerView(request: request)
                    .id(request.id)
                    .environment(\.closePlayer, ClosePlayerAction { windowPlayback = nil })
                    .ignoresSafeArea()
            }
        }
        // The title bar and tabs stay hidden for the whole playback: only the player's own controls show.
        .toolbar(windowPlayback != nil ? .hidden : .automatic, for: .windowToolbar)
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
        case .search:
            #if os(tvOS)
            return .search
            #else
            return .home
            #endif
        }
    }
}
