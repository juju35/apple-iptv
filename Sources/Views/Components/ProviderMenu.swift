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
    /// Adds the provider switcher at the trailing end of the toolbar (on Apple TV, see `tvProviderSwitcher`).
    /// `barHasTitle`: false when the navigation bar holds nothing but the switcher (Home), so it can go
    /// when the switcher moves out of it.
    func providerToolbar(barHasTitle: Bool = true) -> some View {
        #if os(tvOS)
        self  // Placed once on the tab view: `tvProviderSwitcher()`.
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

#if os(tvOS)
extension View {
    /// Apple TV: the switcher level with the tab bar at the top right, set on the tab view itself so it
    /// doesn't move while a tab's content lays out (on each screen it briefly showed lower).
    /// Shown on every tab, Search included.
    func tvProviderSwitcher() -> some View {
        overlay {
            // Same inset from the top and the right edge as the tab bar from the top.
            ProviderMenu()
                .padding(.top, 53)
                .padding(.trailing, 53)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .ignoresSafeArea()
        }
    }
}
#endif

#if os(iOS)
/// The switcher in the toolbar, except on iPhone Duo in landscape, where the status bar and the tab bar
/// run down the sides: then at the top right of the page, as Netflix places the profile. (It used to sit
/// in the side columns, under the network icons or above the side tab bar, where the tab bar's Search
/// button now covers it.)
private struct ProviderToolbarModifier: ViewModifier {
    let barHasTitle: Bool
    @State private var isSideLayout = false

    @State private var viewInsets = EdgeInsets()
    @Environment(\.scenePhase) private var scenePhase

    /// At launch the scene isn't active yet when the first layout reads it: take it anyway (it used to
    /// return nil, leaving the switcher in the toolbar until the next layout).
    private static func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }

    /// Only one side inset: a notched iPhone in landscape has them on both. The window's insets count too:
    /// the view's own drop to zero once Home hides its navigation bar and runs under the status bar.
    private static func isSideLayout(for viewInsets: EdgeInsets) -> Bool {
        guard let scene = activeScene(), let window = scene.keyWindow ?? scene.windows.first else { return false }
        let leading = max(viewInsets.leading, window.safeAreaInsets.left)
        let trailing = max(viewInsets.trailing, window.safeAreaInsets.right)
        return (trailing > 40) != (leading > 40)
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: EdgeInsets.self, of: \.safeAreaInsets) {
                viewInsets = $0
                isSideLayout = Self.isSideLayout(for: $0)
            }
            // The window's insets can settle after the first layout (launch, switching screens).
            .onChange(of: scenePhase) { isSideLayout = Self.isSideLayout(for: viewInsets) }
            .toolbar {
                if !isSideLayout {
                    ToolbarItem(placement: .primaryAction) {
                        ProviderMenu()
                    }
                }
            }
            .toolbar(isSideLayout && !barHasTitle ? .hidden : .automatic, for: .navigationBar)
            .overlay(alignment: .topTrailing) {
                if isSideLayout {
                    // Level with the navigation bar's title where the page has one.
                    ProviderMenu()
                        .sideBubble()
                        .padding(.top, 10)
                        .padding(.trailing, 16)
                        .ignoresSafeArea(.container, edges: barHasTitle ? Edge.Set.top : [])
                }
            }
    }
}
#endif

#if os(iOS)
private extension View {
    /// The side tab bar's Liquid Glass bubble around the switcher (a toolbar item gets one already).
    @ViewBuilder
    func sideBubble() -> some View {
        // Behind the menu, not around it: an interactive glass effect took the taps and the menu never opened.
        if #available(iOS 26, *) {
            padding(8).background { Color.clear.glassEffect(.regular, in: .circle).allowsHitTesting(false) }
        } else {
            padding(8).background(.ultraThinMaterial, in: Circle())
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
                    #if os(tvOS)
                    // Settings live here on Apple TV, not in the tab bar.
                    Label("Settings", systemImage: "gearshape")
                    #else
                    Label("Manage Providers", systemImage: "gearshape")
                    #endif
                }
            }
        } label: {
            #if os(tvOS)
            // A labelled button on Apple TV: initials alone are cryptic from the couch.
            HStack(spacing: 14) {
                ProviderAvatar(provider: selected)
                Text(selected?.name ?? String(localized: "Providers"))
            }
            #else
            ProviderAvatar(provider: selected)
            #endif
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Provider: \(selected?.name ?? String(localized: "none"))")
    }
}

/// The provider's gallery avatar, or the initials of its name in an accent-colored circle.
struct ProviderAvatar: View {
    let name: String
    var avatar: Provider.Avatar?
    var size: CGFloat = Self.defaultSize

    init(provider: Provider?) {
        name = provider?.name ?? ""
        avatar = provider?.avatar
    }

    init(name: String, avatar: Provider.Avatar?, size: CGFloat = Self.defaultSize) {
        self.name = name
        self.avatar = avatar
        self.size = size
    }

    private var initials: String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let letters = words.count > 1 ? words.prefix(2).compactMap(\.first) : Array(name.prefix(2))
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    #if os(tvOS)
    static let defaultSize: CGFloat = 40
    #else
    static let defaultSize: CGFloat = 30
    #endif

    var body: some View {
        Group {
            if let avatar {
                Image(systemName: AvatarGallery.symbol(avatar.symbol))
                    .font(.system(size: size * 0.48, weight: .semibold))
            } else {
                // The usual caption in the toolbar; scaled with the circle in the avatar picker.
                Text(initials)
                    .font(size == Self.defaultSize ? .caption.weight(.bold) : .system(size: size * 0.4, weight: .bold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Circle().fill((avatar.map { AvatarGallery.color($0.color) } ?? Theme.accent).gradient))
        .overlay(Circle().strokeBorder(.white.opacity(0.25)))
    }
}

/// The avatars a provider can take: a symbol on a colored circle.
enum AvatarGallery {
    static let symbols = [
        "tv.fill", "play.tv.fill", "film.fill", "popcorn.fill", "theatermasks.fill", "sportscourt.fill",
        "soccerball", "basketball.fill", "gamecontroller.fill", "music.note", "star.fill", "heart.fill",
        "flame.fill", "bolt.fill", "crown.fill", "sparkles", "moon.stars.fill", "sun.max.fill",
        "leaf.fill", "pawprint.fill", "fish.fill", "globe.europe.africa.fill", "house.fill", "rocket.fill",
    ]

    /// `name` is what's stored; `label` is for VoiceOver.
    struct Swatch {
        let name: String
        let label: LocalizedStringResource
        let color: Color

        init(_ name: String, _ label: LocalizedStringResource, _ color: Color) {
            self.name = name
            self.label = label
            self.color = color
        }
    }

    static let colors: [Swatch] = [
        Swatch("red", "Red", Theme.accent), Swatch("orange", "Orange", .orange), Swatch("yellow", "Yellow", .yellow),
        Swatch("green", "Green", .green), Swatch("mint", "Mint", .mint), Swatch("teal", "Teal", .teal),
        Swatch("blue", "Blue", .blue), Swatch("indigo", "Indigo", .indigo), Swatch("purple", "Purple", .purple),
        Swatch("pink", "Pink", .pink), Swatch("brown", "Brown", .brown), Swatch("gray", "Gray", .gray),
    ]

    /// A symbol from another version's gallery falls back to the TV, rather than a blank circle.
    static func symbol(_ name: String) -> String {
        symbols.contains(name) ? name : "tv.fill"
    }

    static func color(_ name: String) -> Color {
        colors.first { $0.name == name }?.color ?? Theme.accent
    }
}

/// Form section to pick the provider's avatar: initials, or a gallery symbol and its color.
struct AvatarPickerSection: View {
    let name: String
    @Binding var avatar: Provider.Avatar?

    #if os(tvOS)
    private static let cell: CGFloat = 70
    #else
    private static let cell: CGFloat = 40
    #endif

    var body: some View {
        Section("Avatar") {
            HStack {
                Spacer()
                ProviderAvatar(name: name, avatar: avatar, size: Self.cell * 2)
                Spacer()
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cell), spacing: 12)], spacing: 12) {
                cell(selected: avatar == nil, label: Text("Initials")) {
                    ProviderAvatar(name: name, avatar: nil, size: Self.cell)
                } action: {
                    avatar = nil
                }
                ForEach(AvatarGallery.symbols, id: \.self) { symbol in
                    let choice = Provider.Avatar(symbol: symbol, color: avatar?.color ?? AvatarGallery.colors[0].name)
                    // The symbol's own VoiceOver label names it.
                    cell(selected: avatar?.symbol == symbol, label: nil) {
                        ProviderAvatar(name: name, avatar: choice, size: Self.cell)
                    } action: {
                        avatar = choice
                    }
                }
            }
            .padding(.vertical, 6)

            if let current = avatar {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cell), spacing: 12)], spacing: 12) {
                    ForEach(AvatarGallery.colors, id: \.name) { entry in
                        cell(selected: current.color == entry.name, label: Text(entry.label)) {
                            Circle().fill(entry.color.gradient)
                                .frame(width: Self.cell, height: Self.cell)
                        } action: {
                            avatar = Provider.Avatar(symbol: current.symbol, color: entry.name)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    /// A gallery entry, ringed when chosen.
    @ViewBuilder
    private func cell<Content: View>(selected: Bool, label: Text?,
                                     @ViewBuilder content: () -> Content,
                                     action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            content()
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? Color.white : .clear, lineWidth: 2))
                .lockupArtwork()
        }
        .lockupButtonStyle()
        .accessibilityAddTraits(selected ? .isSelected : [])
        if let label {
            button.accessibilityLabel(label)
        } else {
            button
        }
    }
}
