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
    /// above the screen's content at the top right, where focus reaches it by swiping up.
    func providerToolbar() -> some View {
        #if os(tvOS)
        safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                ProviderMenu()
            }
            .padding(.horizontal, 80)
        }
        #else
        toolbar {
            ToolbarItem(placement: .primaryAction) {
                ProviderMenu()
            }
        }
        #endif
    }
}

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
