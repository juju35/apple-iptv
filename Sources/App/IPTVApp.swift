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

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            BrowseView(kind: .live, title: "Live TV")
                .tabItem { Label("Live TV", systemImage: "tv") }
            BrowseView(kind: .movie, title: "Movies")
                .tabItem { Label("Movies", systemImage: "film") }
            BrowseView(kind: .series, title: "Series")
                .tabItem { Label("Series", systemImage: "play.rectangle.on.rectangle") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
        .background(Theme.background)
    }
}
