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
            ProviderMenu()
                .padding(.top, 62)
                .padding(.trailing, 90)
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
    @State private var insets = EdgeInsets()

    /// Status bar column on the trailing side only (a notched iPhone in landscape has insets on both sides).
    /// The top inset isn't checked: it includes the navigation bar.
    private var hasSideStatusBar: Bool {
        insets.trailing > 40 && insets.leading < 10
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: EdgeInsets.self, of: \.safeAreaInsets) { insets = $0 }
            .toolbar {
                if !hasSideStatusBar {
                    ToolbarItem(placement: .primaryAction) {
                        ProviderMenu()
                    }
                }
            }
            .toolbar(hasSideStatusBar && !barHasTitle ? .hidden : .automatic, for: .navigationBar)
            .overlay {
                if hasSideStatusBar {
                    ProviderMenu()
                        .frame(width: insets.trailing)
                        .padding(.top, 125)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
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
    private static let size: CGFloat = 44
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
