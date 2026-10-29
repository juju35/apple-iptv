import SwiftUI

/// Styles that follow each platform's conventions. On Apple TV everything is driven by focus: posters are
/// lockups (the artwork lifts and tilts, the title below stays put), rows get the system focus platter, buttons
/// keep the system's white-on-focus look instead of the brand red, and screens a sheet would show elsewhere take
/// the full screen.
extension View {
    /// Buttons wrapping a poster or an episode still.
    @ViewBuilder
    func lockupButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.borderless)
        #else
        buttonStyle(.plain)
        #endif
    }

    /// The artwork part of a lockup: lifted, tilted and lit by the focus on Apple TV.
    @ViewBuilder
    func lockupArtwork() -> some View {
        #if os(tvOS)
        hoverEffect(.highlight)
        #else
        self
        #endif
    }

    /// List rows (channels, categories): the system focus platter on Apple TV.
    @ViewBuilder
    func rowButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.card)
        #else
        buttonStyle(.plain)
        #endif
    }

    /// The main action of a screen (Play, Resume): the brand red elsewhere, the system button on Apple TV.
    @ViewBuilder
    func primaryActionStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.bordered)
        #else
        buttonStyle(.borderedProminent).tint(Theme.accent)
        #endif
    }

    /// The app's accent, except on Apple TV where focus gives the emphasis.
    @ViewBuilder
    func brandTint() -> some View {
        #if os(tvOS)
        self
        #else
        tint(Theme.accent)
        #endif
    }

    /// Detail screens: a sheet elsewhere, the full screen on Apple TV (a sheet is a small card there).
    @ViewBuilder
    func detailPresentation<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(tvOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item, content: content)
        #endif
    }
}

/// Spacing between lockups: Apple TV needs room for the focus lift.
enum LockupMetrics {
    #if os(tvOS)
    static let rowSpacing: CGFloat = 48
    static let gridSpacing: CGFloat = 48
    static let gridRowSpacing: CGFloat = 64
    #else
    static let rowSpacing: CGFloat = 14
    static let gridSpacing: CGFloat = 16
    static let gridRowSpacing: CGFloat = 22
    #endif
}
