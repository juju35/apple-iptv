import SwiftUI

/// Artwork drawn from a title when a channel, film or series has no image of its own:
/// a gradient picked from the title (stable across launches) with the title set on it.
struct GeneratedArtwork: View {
    let title: String
    let kind: MediaKind
    /// Hero banners leave the title to their own overlay.
    var showsTitle = true

    private static let palettes: [(Color, Color)] = [
        (Color(red: 0.55, green: 0.10, blue: 0.16), Color(red: 0.12, green: 0.02, blue: 0.06)),
        (Color(red: 0.12, green: 0.27, blue: 0.55), Color(red: 0.03, green: 0.06, blue: 0.16)),
        (Color(red: 0.07, green: 0.40, blue: 0.38), Color(red: 0.02, green: 0.10, blue: 0.12)),
        (Color(red: 0.52, green: 0.30, blue: 0.08), Color(red: 0.14, green: 0.06, blue: 0.02)),
        (Color(red: 0.36, green: 0.16, blue: 0.52), Color(red: 0.08, green: 0.03, blue: 0.15)),
        (Color(red: 0.20, green: 0.22, blue: 0.26), Color(red: 0.05, green: 0.05, blue: 0.07)),
    ]

    /// djb2: `hashValue` changes from one launch to the next.
    private var seed: Int {
        title.unicodeScalars.reduce(5381) { ($0 &* 33 &+ Int($1.value)) & 0x7fff_ffff }
    }

    private var palette: (Color, Color) { Self.palettes[seed % Self.palettes.count] }

    private var symbol: String {
        switch kind {
        case .live: return "dot.radiowaves.left.and.right"
        case .movie: return "film"
        case .series: return "play.rectangle.on.rectangle"
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack(alignment: kind == .live ? .center : .bottomLeading) {
                LinearGradient(colors: [palette.0, palette.1], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.white.opacity(0.18), .clear], center: .topLeading,
                               startRadius: 0, endRadius: side * 1.2)
                Image(systemName: symbol)
                    .font(.system(size: side * 0.6, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.07))
                    .offset(x: side * 0.25, y: -side * 0.2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsTitle {
                    Text(kind == .live ? title : title.uppercased())
                        .font(.system(size: side * (kind == .live ? 0.16 : 0.15), weight: .heavy))
                        .tracking(kind == .live ? 0 : 0.5)
                        .multilineTextAlignment(kind == .live ? .center : .leading)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                        .padding(side * 0.1)
                }
            }
            // One flattened layer instead of gradients, symbol and shadowed text composited per frame.
            .drawingGroup()
        }
    }
}
