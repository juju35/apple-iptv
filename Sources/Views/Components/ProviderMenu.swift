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
    /// Adds the provider switcher at the trailing end of the toolbar (not on tvOS, whose tab bar has no room).
    func providerToolbar() -> some View {
        #if os(tvOS)
        self
        #else
        toolbar {
            ToolbarItem(placement: .primaryAction) {
                ProviderMenu()
            }
        }
        #endif
    }
}

#if !os(tvOS)
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
            ProviderAvatar(name: selected?.name ?? "")
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Provider: \(selected?.name ?? "none")")
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

    var body: some View {
        Text(initials)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Theme.accent.gradient))
            .overlay(Circle().strokeBorder(.white.opacity(0.25)))
    }
}
#endif
