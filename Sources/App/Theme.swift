import SwiftUI

/// Dark, cinematic theme (Netflix-inspired, original palette).
enum Theme {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.07)
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let accent = Color(red: 0.90, green: 0.12, blue: 0.20)
    static let textSecondary = Color.white.opacity(0.65)
    /// Secondary text in list rows: on Apple TV the focused row turns white, so follow the row's own
    /// (focus-aware) foreground instead of a fixed light grey.
    static var rowSecondary: AnyShapeStyle {
        #if os(tvOS)
        AnyShapeStyle(.secondary)
        #else
        AnyShapeStyle(textSecondary)
        #endif
    }

    static let posterAspect: CGFloat = 2.0 / 3.0
    static let cardCornerRadius: CGFloat = 10

    #if os(tvOS)
    static let posterWidth: CGFloat = 260
    static let heroHeight: CGFloat = 780
    static let sidebarWidth: CGFloat = 380
    static let channelListMinWidth: CGFloat = 520
    static let channelListMaxWidth: CGFloat = 700
    static let channelLogoWidth: CGFloat = 110
    #elseif os(macOS)
    static let posterWidth: CGFloat = 170
    static let heroHeight: CGFloat = 460
    static let sidebarWidth: CGFloat = 230
    static let channelListMinWidth: CGFloat = 300
    static let channelListMaxWidth: CGFloat = 440
    static let channelLogoWidth: CGFloat = 64
    #else
    static let posterWidth: CGFloat = 120
    static let heroHeight: CGFloat = 420
    static let sidebarWidth: CGFloat = 240
    static let channelListMinWidth: CGFloat = 300
    static let channelListMaxWidth: CGFloat = 420
    static let channelLogoWidth: CGFloat = 64
    #endif
}
