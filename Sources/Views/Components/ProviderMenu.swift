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
/// run down the sides: under the network icons when the status bar shows on the trailing edge, else
/// under the side tab bar.
private struct ProviderToolbarModifier: ViewModifier {
    let barHasTitle: Bool
    /// Where the switcher's centre goes, in window coordinates (as measured on screenshots), when it
    /// leaves the toolbar.
    @State private var sideCentre: CGPoint?

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
    /// the view's own drop to zero once Home hides its navigation bar and runs under the status bar,
    /// which sent the switcher back to the (hidden) toolbar.
    private static func sideCentre(for viewInsets: EdgeInsets) -> CGPoint? {
        guard let scene = activeScene(), let window = scene.keyWindow ?? scene.windows.first else { return nil }
        let leading = max(viewInsets.leading, window.safeAreaInsets.left)
        let trailing = max(viewInsets.trailing, window.safeAreaInsets.right)
        guard (trailing > 40) != (leading > 40) else { return nil }
        let insets = EdgeInsets(top: 0, leading: leading, bottom: 0, trailing: trailing)
        let bounds = window.bounds
        let statusBarShown = scene.statusBarManager?.isStatusBarHidden == false
        if insets.trailing > 40 && statusBarShown {
            // Under the status column's network icons, measured on screenshots (UIKit reports the column
            // as a 2 pt strip at the top); the cover screen (portrait) sets them lower.
            let isCoverScreen = bounds.height > bounds.width
            // Inner screen measured on 2x screenshots, cover screen on 3x ones; y leaves room for the bubble.
            return CGPoint(x: bounds.maxX - (isCoverScreen ? 48 : 51), y: isCoverScreen ? 193 : 144)
        }
        // At the top of the black band holding the side tab bar, above it and centred on it (measured on
        // screenshots: UIKit's `UITabBar` isn't where the floating bar is drawn).
        // Centred on the tab bar (48 pt from the edge, measured on 3x screenshots). On the left the front
        // camera sits in the top corner, so the switcher goes lower, just above the tab bar.
        return CGPoint(x: insets.leading > 40 ? 48 : bounds.maxX - 48, y: insets.leading > 40 ? 146 : 40)
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: EdgeInsets.self, of: \.safeAreaInsets) {
                viewInsets = $0
                sideCentre = Self.sideCentre(for: $0)
            }
            // The window's insets can settle after the first layout (launch, switching screens).
            .onChange(of: scenePhase) { sideCentre = Self.sideCentre(for: viewInsets) }
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
                            .sideBubble()
                            .position(x: sideCentre.x - origin.x, y: sideCentre.y - origin.y)
                    }
                    .ignoresSafeArea()
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
        if #available(iOS 26, *) {
            padding(8).glassEffect(.regular.interactive(), in: .circle)
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
