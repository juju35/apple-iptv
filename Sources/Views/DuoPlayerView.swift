#if os(iOS)
import SwiftUI
import AVKit
import Combine

/// iPhone Duo laptop-mode player (iOS 27.1+).
///
/// Uses the fold's reserved *division* region (Apple's recommended layout API,
/// rather than the hinge angle): while the device is half-folded with a
/// horizontal hinge, the video fills the upper panel and Netflix-style
/// transport controls fill the lower panel. Flat or fully open, it falls back
/// to the standard system player.
@available(iOS 27.1, *)
struct FoldAwarePlayerView: View {
    let player: AVPlayer
    let title: String
    let onClose: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let fold = proxy.reservedRegions(kind: .division)
                .first { $0.isActive && $0.frame.width > $0.frame.height }

            if let fold {
                VStack(spacing: 0) {
                    VideoSurface(player: player)
                        .frame(height: max(0, fold.frame.minY))
                        .frame(maxWidth: .infinity)
                        .background(Color.black)

                    Color.black
                        .frame(height: fold.frame.height)

                    TransportControls(player: player, title: title, onClose: onClose)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.background)
                }
                .ignoresSafeArea()
            } else {
                StandardPlayerView(player: player, onClose: onClose)
            }
        }
    }
}

/// Raw AVPlayerLayer surface (no system chrome) for the upper fold panel.
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer

    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

/// Netflix-style transport panel: title row, big center transport, scrubber.
struct TransportControls: View {
    let player: AVPlayer
    let title: String
    let onClose: () -> Void

    @State private var isPlaying = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var timeObserver: Any?

    private var isLive: Bool { duration <= 0 || !duration.isFinite }

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
                .buttonStyle(.plain)
            }

            Spacer()

            HStack(spacing: 56) {
                if !isLive {
                    transportButton("gobackward.10") { seek(by: -10) }
                }
                transportButton(isPlaying ? "pause.fill" : "play.fill", size: 54) {
                    togglePlayback()
                }
                if !isLive {
                    transportButton("goforward.10") { seek(by: 10) }
                }
            }

            Spacer()

            if isLive {
                Label("LIVE", systemImage: "circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
            } else {
                VStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { currentTime },
                            set: { currentTime = $0 }
                        ),
                        in: 0...max(duration, 1)
                    ) { editing in
                        isScrubbing = editing
                        if !editing {
                            player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
                        }
                    }
                    .tint(Theme.accent)

                    HStack {
                        Text(timeString(currentTime))
                        Spacer()
                        Text("-" + timeString(max(0, duration - currentTime)))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(28)
        .foregroundStyle(.white)
        .onAppear(perform: attachObserver)
        .onDisappear(perform: detachObserver)
    }

    private func transportButton(_ systemName: String, size: CGFloat = 32,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Playback

    private func togglePlayback() {
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    private func seek(by seconds: Double) {
        let target = max(0, min(duration, currentTime + seconds))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    private func attachObserver() {
        isPlaying = player.timeControlStatus != .paused
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { time in
            if !isScrubbing { currentTime = time.seconds }
            if let itemDuration = player.currentItem?.duration.seconds,
               itemDuration.isFinite {
                duration = itemDuration
            }
        }
    }

    private func detachObserver() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}
#endif
