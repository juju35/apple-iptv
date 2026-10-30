import SwiftUI

@main
struct IPTVApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var epg = EPGStore()
    @StateObject private var homeLayout = HomeLayoutStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(epg)
                .environmentObject(homeLayout)
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
    @EnvironmentObject private var store: AppStore
    #if os(tvOS)
    // No Settings tab on Apple TV (see `showingSettings`).
    @State private var tab: MainTab = Demo.isOn && Demo.screen.tab != .settings ? Demo.screen.tab : .home
    #else
    @State private var tab: MainTab = Demo.isOn ? Demo.screen.tab : .home
    #endif
    /// Bumped when a tab is left, so it comes back reset (scroll, filters, selection). Artwork stays
    /// in `ImageLoader`'s memory cache and shows again at once.
    @State private var resets: [MainTab: Int] = [:]
    #if os(tvOS)
    @State private var launchFocusPlaced = false
    /// Screenshot mode: `-demoScreen settings` opens it.
    @State private var showingSettings = Demo.isOn && Demo.screen.tab == .settings
    #endif
    #if os(macOS)
    /// Player shown over the whole window: macOS sheets can't fill it.
    @State private var windowPlayback: PlaybackRequest?
    #endif

    var body: some View {
        TabView(selection: $tab) {
            #if os(tvOS)
            // First, as in Apple's own apps: the only place to search on Apple TV.
            SearchView()
                .id(resets[.search, default: 0])
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(MainTab.search)
            #endif
            HomeView()
                .id(resets[.home, default: 0])
                #if os(tvOS)
                // At launch the focus goes to the Home tab in the tab bar, not to the hero's Play button:
                // the content can't take it until the tab bar has.
                .disabled(!launchFocusPlaced)
                .task {
                    try? await Task.sleep(for: .milliseconds(600))
                    launchFocusPlaced = true
                }
                #endif
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(MainTab.home)
            LiveTVView()
                .id(resets[.live, default: 0])
                .tabItem { Label("Live TV", systemImage: "tv") }
                .tag(MainTab.live)
            // No empty tabs: a provider with no movies or no series doesn't get their tab.
            if !store.missingKinds.contains(.movie) {
                BrowseView(kind: .movie, title: String(localized: "Movies"))
                    .id(resets[.movies, default: 0])
                    .tabItem { Label("Movies", systemImage: "film") }
                    .tag(MainTab.movies)
            }
            if !store.missingKinds.contains(.series) {
                BrowseView(kind: .series, title: String(localized: "Series"))
                    .id(resets[.series, default: 0])
                    .tabItem { Label("Series", systemImage: "play.rectangle.on.rectangle") }
                    .tag(MainTab.series)
            }
            #if !os(tvOS)
            // Apple TV opens Settings from the provider menu: the tab bar keeps to content.
            SettingsView()
                .id(resets[.settings, default: 0])
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
            #endif
        }
        .brandTint()
        .onChange(of: tab) { left, _ in resets[left, default: 0] += 1 }
        // The shown tab went away (e.g. switched to a provider without series): back to Home.
        .onChange(of: store.missingKinds) { _, missing in
            if (tab == .movies && missing.contains(.movie)) || (tab == .series && missing.contains(.series)) {
                tab = .home
            }
        }
        #if os(tvOS)
        .tvProviderSwitcher()
        #endif
        .background(Theme.background)
        #if os(tvOS)
        .environment(\.showSettings, ShowSettingsAction { showingSettings = true })
        .fullScreenCover(isPresented: $showingSettings) {
            // Opaque: a full-screen cover is transparent on Apple TV and the tab showed through.
            SettingsView()
                .background(Theme.background.ignoresSafeArea())
        }
        #else
        .environment(\.showSettings, ShowSettingsAction { tab = .settings })
        #endif
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
