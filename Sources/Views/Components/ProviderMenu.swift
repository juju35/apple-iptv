import SwiftUI

extension EnvironmentValues {
    /// Switches to the Settings tab; set by `MainTabView`.
    @Entry var showSettings: ShowSettingsAction?
}

/// Equatable wrapper so re-setting the environment value doesn't invalidate readers on every update.
/// All instances compare equal: `MainTabView` always installs the same behavior (select the Settings tab).
struct ShowSettingsAction: Equatable {
    let action: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension View {
    /// Adds the provider switcher at the trailing end of the toolbar; on Apple TV, whose tab bar has no room,
    /// level with the tab bar at the top right (over the content, which keeps its full height).
    /// `barHasTitle`: false when the navigation bar holds nothing but the switcher (Home), so it can go
    /// when the switcher moves out of it.
    func providerToolbar(barHasTitle: Bool = true) -> some View {
        #if os(tvOS)
        overlay {
            // Same inset from the top and the right edge as the tab bar from the top.
            ProviderMenu()
                .padding(.top, 53)
                .padding(.trailing, 53)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .ignoresSafeArea()
        }
        #elseif os(iOS)
        modifier(ProviderToolbarModifier(barHasTitle: barHasTitle))
        #else
        toolbar {
            ToolbarItem(placement: .primaryAction) {
                ProviderMenu()
            }
        }
        #endif
    }
}

#if os(iOS)
/// The switcher in the toolbar, except on iPhone Duo in landscape, where the status bar and the tab bar
/// run down the sides: under the network icons when the status bar shows on the trailing edge, else
/// under the side tab bar.
private struct ProviderToolbarModifier: ViewModifier {
    let barHasTitle: Bool
    /// Where the switcher's centre goes, in window coordinates (as measured on screenshots), when it
    /// leaves the toolbar.
    @State private var sideCentre: CGPoint?

    private static func activeScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    /// Only one side inset: a notched iPhone in landscape has them on both.
    private static func sideCentre(for insets: EdgeInsets) -> CGPoint? {
        let isSide = (insets.trailing > 40) != (insets.leading > 40)
        guard isSide, let scene = activeScene(), let window = scene.keyWindow ?? scene.windows.first else {
            return nil
        }
        let bounds = window.bounds
        let statusBarShown = scene.statusBarManager?.isStatusBarHidden == false
        if insets.trailing > 40 && statusBarShown {
            // Under the status column's network icons, measured on screenshots (UIKit reports the column
            // as a 2 pt strip at the top); the cover screen (portrait) sets them lower.
            let isCoverScreen = bounds.height > bounds.width
            return CGPoint(x: bounds.maxX - (isCoverScreen ? 48 : 51), y: isCoverScreen ? 193 : 140)
        }
        // At the top of the black band holding the side tab bar, above it and centred on it (measured on
        // screenshots: UIKit's `UITabBar` isn't where the floating bar is drawn).
        return CGPoint(x: insets.leading > 40 ? 71 : bounds.maxX - 71, y: 40)
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: EdgeInsets.self, of: \.safeAreaInsets) { sideCentre = Self.sideCentre(for: $0) }
            .toolbar {
                if sideCentre == nil {
                    ToolbarItem(placement: .primaryAction) {
                        ProviderMenu()
                    }
                }
            }
            .toolbar(sideCentre != nil && !barHasTitle ? .hidden : .automatic, for: .navigationBar)
            .overlay {
                if let sideCentre {
                    // The view doesn't start at the window's origin (the side tab bar takes room):
                    // convert from window coordinates.
                    GeometryReader { proxy in
                        let origin = proxy.frame(in: .global).origin
                        ProviderMenu()
                            .position(x: sideCentre.x - origin.x, y: sideCentre.y - origin.y)
                    }
                    .ignoresSafeArea()
                }
            }
    }
}
#endif

/// Profile-style button: the selected provider's initials; its menu switches providers.
struct ProviderMenu: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.showSettings) private var showSettings

    var body: some View {
        let selected = store.selectedProvider
        Menu {
            Section("Providers") {
                ForEach(store.providers) { provider in
                    Button {
                        store.selectedProviderID = provider.id
                    } label: {
                        if provider.id == selected?.id {
                            Label(provider.name, systemImage: "checkmark")
                        } else {
                            Text(provider.name)
                        }
                    }
                }
            }
            if let showSettings {
                Button(action: showSettings.action) {
                    Label("Manage Providers", systemImage: "gearshape")
                }
            }
        } label: {
            #if os(tvOS)
            // A labelled button on Apple TV: initials alone are cryptic from the couch.
            HStack(spacing: 14) {
                ProviderAvatar(name: selected?.name ?? "")
                Text(selected?.name ?? String(localized: "Providers"))
            }
            #else
            ProviderAvatar(name: selected?.name ?? "")
            #endif
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Provider: \(selected?.name ?? String(localized: "none"))")
    }
}

/// Initials of a provider name in an accent-colored circle.
struct ProviderAvatar: View {
    let name: String

    private var initials: String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let letters = words.count > 1 ? words.prefix(2).compactMap(\.first) : Array(name.prefix(2))
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    #if os(tvOS)
    private static let size: CGFloat = 40
    #else
    private static let size: CGFloat = 30
    #endif

    var body: some View {
        Text(initials)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: Self.size, height: Self.size)
            .background(Circle().fill(Theme.accent.gradient))
            .overlay(Circle().strokeBorder(.white.opacity(0.25)))
    }
}
