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
/// The switcher in the toolbar, except when the status bar runs down the trailing edge (iPhone Duo in
/// landscape): it then sits in that column under the network icons, above the side tab bar.
private struct ProviderToolbarModifier: ViewModifier {
    let barHasTitle: Bool
    /// The status bar's frame when it runs down the trailing edge, else nil.
    @State private var sideStatusBar: CGRect?

    /// The status bar column at the trailing edge, as UIKit reports it, in the window's coordinates: its
    /// position differs between the inner screen and the cover screen, so the switcher follows it.
    /// Measured against the window, not `UIScreen`, which can describe the other screen.
    private static func trailingStatusBarFrame() -> CGRect {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let window = (scene?.keyWindow ?? scene?.windows.first)?.bounds ?? .zero
        let reported = scene?.statusBarManager?.statusBarFrame ?? .zero
        print("[ProviderMenu] window \(window), status bar \(reported)")
        if reported.height > reported.width, reported.minX > window.midX, reported.maxX <= window.maxX + 1 {
            return reported
        }
        // Not reported as a column: the inner screen's measured one (icons centred 51 pt from the edge).
        return CGRect(x: window.maxX - 102, y: 0, width: 102, height: 113)
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: EdgeInsets.self, of: \.safeAreaInsets) { insets in
                // Trailing inset only: a notched iPhone in landscape has them on both sides.
                sideStatusBar = insets.trailing > 40 && insets.leading < 10 ? Self.trailingStatusBarFrame() : nil
            }
            .toolbar {
                if sideStatusBar == nil {
                    ToolbarItem(placement: .primaryAction) {
                        ProviderMenu()
                    }
                }
            }
            .toolbar(sideStatusBar != nil && !barHasTitle ? .hidden : .automatic, for: .navigationBar)
            .overlay {
                if let frame = sideStatusBar {
                    // Just under the network icons, centred on the status bar column.
                    Color.clear
                        .overlay(alignment: .topLeading) {
                            ProviderMenu()
                                .position(x: frame.midX, y: frame.maxY + 27)
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
