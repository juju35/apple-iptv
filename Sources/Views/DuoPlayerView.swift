#if os(iOS)
import SwiftUI
import AVFoundation

/// Lays a player out around the fold of iPhone Duo (iOS 27.1+), Netflix-style.
///
/// Uses the active *division* reserved region (Apple's recommended layout API, rather than
/// the hinge angle); it exists only while the device is partially folded:
/// - horizontal fold (laptop / tabletop): video above the fold, controls below;
/// - vertical fold (book): video on the leading side, controls on the trailing side.
/// Flat, closed or on any other iPhone, the regular full-screen player is shown.
/// Shared by the system (AVFoundation) and VLC engines.
@available(iOS 27.1, *)
struct FoldAwarePlayerLayout<Video: View, Controls: View, Flat: View>: View {
    private let video: Video
    private let controls: Controls
    private let flat: Flat

    init(
        @ViewBuilder video: () -> Video,
        @ViewBuilder controls: () -> Controls,
        @ViewBuilder flat: () -> Flat
    ) {
        self.video = video()
        self.controls = controls()
        self.flat = flat()
    }

    var body: some View {
        GeometryReader { proxy in
            // Only active regions are returned: none while flat or closed.
            let fold = proxy.reservedRegions(kind: .division).first?.frame

            Group {
                if let fold, fold.width > fold.height {
                    tabletop(fold: fold, size: proxy.size)
                } else if let fold {
                    book(fold: fold, size: proxy.size)
                } else {
                    flat
                }
            }
            .animation(.smooth, value: fold)
        }
    }

    private func tabletop(fold: CGRect, size: CGSize) -> some View {
        VStack(spacing: 0) {
            video
                .frame(maxWidth: .infinity)
                .frame(height: max(fold.minY, 0))
            Color.black
                .frame(height: fold.height)
            controls
                .frame(maxWidth: .infinity)
                .frame(height: max(size.height - fold.maxY, 0))
                .background(Theme.background)
        }
    }

    private func book(fold: CGRect, size: CGSize) -> some View {
        HStack(spacing: 0) {
            video
                .frame(width: max(fold.minX, 0))
                .frame(maxHeight: .infinity)
            Color.black
                .frame(width: fold.width)
            controls
                .frame(width: max(size.width - fold.maxX, 0))
                .frame(maxHeight: .infinity)
                .background(Theme.background)
        }
    }
}

/// Netflix-style transport panel shown on the controls side of the fold.
struct FoldControlsPanel: View {
    let title: String
    let isPlaying: Bool
    let isSeekable: Bool
    /// Playback progress, 0…1; only used when `isSeekable`.
    @Binding var position: Double
    let elapsed: String
    let remaining: String
    var onScrubbingChanged: (Bool) -> Void = { _ in }
    let onPlayPause: () -> Void
    let onSkip: (Int) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 56) {
                if isSeekable {
                    transportButton("gobackward.10") { onSkip(-10) }
                }
                transportButton(isPlaying ? "pause.fill" : "play.fill", size: 54, action: onPlayPause)
                if isSeekable {
                    transportButton("goforward.10") { onSkip(10) }
                }
            }

            Spacer(minLength: 0)

            if isSeekable {
                VStack(spacing: 6) {
                    Slider(value: $position, in: 0...1, onEditingChanged: onScrubbingChanged)
                        .tint(Theme.accent)
                    HStack {
                        Text(elapsed)
                        Spacer()
                        Text(remaining)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                }
            } else {
                Label("LIVE", systemImage: "circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .buttonStyle(.plain)
        .padding(28)
        .foregroundStyle(.white)
    }

    private func transportButton(_ systemName: String, size: CGFloat = 32,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        }
    }
}

// MARK: - System engine

/// AVFoundation player wired into the fold layout.
@available(iOS 27.1, *)
struct FoldAwarePlayerView: View {
    let player: AVPlayer
    let title: String
    let onClose: () -> Void

    var body: some View {
        FoldAwarePlayerLayout {
            VideoSurface(player: player)
        } controls: {
            AVTransportControls(player: player, title: title, onClose: onClose)
        } flat: {
            StandardPlayerView(player: player, onClose: onClose)
        }
    }
}

/// Raw AVPlayerLayer surface (no system chrome) for the video side of the fold.
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer

    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }

        /// A layer that changes window (fold layout switch, other screen) can stop showing the
        /// picture while the sound goes on: attach the player again.
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, let player = playerLayer?.player else { return }
            playerLayer?.player = nil
            playerLayer?.player = player
        }
    }

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer?.player = player
        view.playerLayer?.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.playerLayer?.player = player
    }
}

/// Feeds AVPlayer state into `FoldControlsPanel`.
struct AVTransportControls: View {
    let player: AVPlayer
    let title: String
    let onClose: () -> Void

    @State private var isPlaying = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var timeObserver: Any?

    private var isSeekable: Bool { duration > 0 && duration.isFinite }

    var body: some View {
        FoldControlsPanel(
            title: title,
            isPlaying: isPlaying,
            isSeekable: isSeekable,
            position: Binding(
                get: { isSeekable ? currentTime / duration : 0 },
                set: { currentTime = $0 * duration }
            ),
            elapsed: Self.timeString(currentTime),
            remaining: "-" + Self.timeString(max(0, duration - currentTime)),
            onScrubbingChanged: { editing in
                isScrubbing = editing
                if !editing {
                    player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
                }
            },
            onPlayPause: togglePlayback,
            onSkip: { seek(by: Double($0)) },
            onClose: onClose
        )
        .onAppear(perform: attachObserver)
        .onDisappear(perform: detachObserver)
    }

    private func togglePlayback() {
        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
    }

    private func seek(by seconds: Double) {
        let target = max(0, min(duration, currentTime + seconds))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    private func attachObserver() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { time in
            isPlaying = player.timeControlStatus != .paused
            if !isScrubbing { currentTime = time.seconds }
            if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite {
                duration = itemDuration
            }
        }
    }

    private func detachObserver() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }

    private static func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}
#endif
