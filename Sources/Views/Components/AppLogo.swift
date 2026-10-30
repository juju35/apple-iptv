import SwiftUI

/// The app icon's glyph (a screen with a play triangle on a stand, from design/render_icons.py),
/// drawn in the brand red: shown while the provider's lists load, gently pulsing.
struct AppLogo: View {
    var size: CGFloat = 120
    var isPulsing = true
    @State private var dimmed = false

    var body: some View {
        Canvas { context, canvasSize in
            // Geometry in the icon's 1024-point space, cropped to the glyph (x 180…844, y 234…772).
            let scale = canvasSize.width / 664
            func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
                CGRect(x: (x - 180) * scale, y: (y - 234) * scale, width: width * scale, height: height * scale)
            }
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: (x - 180) * scale, y: (y - 234) * scale)
            }
            let red = GraphicsContext.Shading.color(Theme.accent)
            let screen = Path(roundedRect: rect(196, 250, 632, 430), cornerRadius: 104 * scale, style: .continuous)
            context.fill(screen, with: .color(Theme.accent.opacity(0.18)))
            context.stroke(screen, with: red, lineWidth: 32 * scale)
            var play = Path()
            play.move(to: point(452, 386))
            play.addLine(to: point(452, 544))
            play.addLine(to: point(589, 465))
            play.closeSubpath()
            context.fill(play, with: red)
            context.stroke(play, with: red, style: StrokeStyle(lineWidth: 58 * scale, lineJoin: .round))
            context.fill(Path(roundedRect: rect(400, 732, 224, 40), cornerRadius: 20 * scale), with: red)
        }
        .frame(width: size, height: size * 538 / 664)
        .opacity(dimmed ? 0.45 : 1)
        .onAppear {
            guard isPulsing else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dimmed = true }
        }
        .accessibilityHidden(true)
    }
}
