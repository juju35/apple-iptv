import SwiftUI

// MARK: - Buttons

#if !os(tvOS)
/// Netflix's main action: a white button with black text (Play, Resume). Apple TV keeps the system button.
struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .tint(.black)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .opacity(isEnabled ? 1 : 0.6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The grey button next to it (My List, Start Over, More Info).
struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.12 : 0.2))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Posters and stills: shrink a little under the finger, lift a little under the pointer (iPad, Mac).
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableCard(configuration: configuration)
    }

    private struct PressableCard: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.95 : (isHovered ? 1.04 : 1))
                .brightness(isHovered ? 0.04 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.68), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.18), value: isHovered)
                .onHover { isHovered = $0 }
                .contentShape(Rectangle())
        }
    }
}

/// Netflix's icon-over-caption actions under the Play button (My List).
struct IconActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .frame(height: 28)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(minWidth: 76)
            .foregroundStyle(.white)
        }
        .buttonStyle(PressableCardStyle())
    }
}
#endif

// MARK: - Top 10

/// Netflix's Top 10 lockup: the rank in large outlined digits, the poster overlapping it.
struct RankedPosterCard: View {
    let rank: Int
    let item: MediaItem
    let width: CGFloat

    private var number: some View {
        Text(verbatim: "\(rank)")
            .font(.system(size: width * 0.95, weight: .black, design: .rounded))
            .kerning(rank >= 10 ? -width * 0.08 : 0)
            .lineLimit(1)
            .fixedSize()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: -width * 0.16) {
            // Outline: four offset white copies under a background-coloured fill.
            ZStack {
                number.foregroundStyle(.white.opacity(0.7)).offset(x: -2, y: -2)
                number.foregroundStyle(.white.opacity(0.7)).offset(x: 2, y: -2)
                number.foregroundStyle(.white.opacity(0.7)).offset(x: -2, y: 2)
                number.foregroundStyle(.white.opacity(0.7)).offset(x: 2, y: 2)
                number.foregroundStyle(Theme.background)
            }
            .offset(y: width * 0.12)
            .accessibilityHidden(true)
            PosterCard(item: item, width: width, showsTitle: false)
                .lockupArtworkShadow()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(rank). \(item.name)"))
    }
}

extension View {
    /// Lifts the poster off the rank digits behind it.
    fileprivate func lockupArtworkShadow() -> some View {
        shadow(color: .black.opacity(0.6), radius: 8, x: -4, y: 0)
    }
}

// MARK: - Loading

/// A soft light sweeping across placeholders while the catalogue loads.
private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, .white.opacity(0.09), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.5)
                        .offset(x: phase * proxy.size.width * 1.5)
                }
                .mask { content }
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

/// Home before its lists arrive: the shape of the page (banner, rows of posters), shimmering.
struct HomeSkeleton: View {
    let posterWidth: CGFloat

    private var block: some ShapeStyle { Theme.surface }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            #if !os(tvOS)
            Rectangle().fill(block).frame(height: Theme.heroHeight * 0.8)
            #endif
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 4).fill(block)
                        .frame(width: posterWidth * 1.3, height: 18)
                    HStack(spacing: LockupMetrics.rowSpacing) {
                        ForEach(0..<8, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: Theme.cardCornerRadius).fill(block)
                                .frame(width: posterWidth, height: posterWidth / Theme.posterAspect)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .modifier(Shimmer())
        .accessibilityElement()
        .accessibilityLabel("Loading…")
    }
}
