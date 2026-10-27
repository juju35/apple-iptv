import SwiftUI

/// Dark, cinematic theme (Netflix-inspired, original palette).
enum Theme {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.07)
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let accent = Color(red: 0.90, green: 0.12, blue: 0.20)
    static let textSecondary = Color.white.opacity(0.65)

    static let posterAspect: CGFloat = 2.0 / 3.0
    static let cardCornerRadius: CGFloat = 10

    #if os(tvOS)
    static let posterWidth: CGFloat = 260
    static let heroHeight: CGFloat = 640
    #elseif os(macOS)
    static let posterWidth: CGFloat = 170
    static let heroHeight: CGFloat = 460
    #else
    static let posterWidth: CGFloat = 120
    static let heroHeight: CGFloat = 420
    #endif
}
