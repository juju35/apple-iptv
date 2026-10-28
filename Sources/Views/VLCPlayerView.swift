import SwiftUI
import VLCKitSPM

/// Drives a `VLCMediaPlayer` and exposes its state to SwiftUI.
@MainActor
@Observable
final class VLCPlayerController: NSObject, VLCMediaPlayerDelegate {
    let player = VLCMediaPlayer()

    private(set) var isPlaying = false
    private(set) var isBuffering = true
    private(set) var isSeekable = false
    private(set) var errorMessage: String?
    /// 0…1 progress; only meaningful when `isSeekable`.
    var position: Float = 0
    private(set) var elapsedText = "--:--"
    private(set) var remainingText = "--:--"

    override init() {
        super.init()
        player.delegate = self
    }

    func start(_ request: PlaybackRequest) {
        let media = VLCMedia(url: request.url)
        media.addOption(":network-caching=1500")
        media.addOption(":http-reconnect")
        if let userAgent = request.headers["User-Agent"] {
            media.addOption(":http-user-agent=\(userAgent)")
        }
        player.media = media
        print("[VLC] playing \(request.url.absoluteString)")
        player.play()
    }

    func stop() {
        player.stop()
        player.drawable = nil
    }

    func togglePlayPause() {
        if player.isPlaying { player.pause() } else { player.play() }
    }

    func seek(to fraction: Float) {
        guard player.isSeekable else { return }
        player.position = fraction
    }

    func jump(seconds: Int32) {
        guard player.isSeekable else { return }
        if seconds >= 0 { player.jumpForward(seconds) } else { player.jumpBackward(-seconds) }
    }

    // MARK: - VLCMediaPlayerDelegate (VLCKit posts these on the main thread)

    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        MainActor.assumeIsolated { syncState() }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        MainActor.assumeIsolated { syncTime() }
    }

    private func syncState() {
        let state = player.state
        isPlaying = player.isPlaying
        isSeekable = player.isSeekable
        switch state {
        case .opening, .buffering:
            isBuffering = true
        case .playing, .paused, .esAdded:
            isBuffering = false
        case .error:
            isBuffering = false
            errorMessage = "VLC could not open this stream."
        case .ended, .stopped:
            isBuffering = false
        @unknown default:
            break
        }
    }

    private func syncTime() {
        isBuffering = false
        if player.isSeekable {
            position = player.position
            elapsedText = player.time.stringValue
            remainingText = player.remainingTime?.stringValue ?? "--:--"
        } else {
            elapsedText = "LIVE"
            remainingText = ""
        }
    }
}

// MARK: - Video surface

/// Platform view VLC renders into.
#if os(macOS)
private struct VLCVideoSurface: NSViewRepresentable {
    let player: VLCMediaPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        player.drawable = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#else
private struct VLCVideoSurface: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        player.drawable = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif

// MARK: - View

/// VLC-backed player with minimal transport controls, used for containers AVFoundation can't play.
struct VLCPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let request: PlaybackRequest

    @State private var controller = VLCPlayerController()
    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            VLCVideoSurface(player: controller.player)
                .ignoresSafeArea()

            if let message = controller.errorMessage {
                errorOverlay(message)
            } else if controller.isBuffering {
                ProgressView().tint(.white)
            }

            if controlsVisible && controller.errorMessage == nil {
                controls
            }
        }
        .background(Color.black.ignoresSafeArea())
        #if !os(tvOS)
        .contentShape(Rectangle())
        .onTapGesture { toggleControls() }
        #endif
        .onAppear {
            controller.start(request)
            scheduleHide()
        }
        .onDisappear {
            hideControlsTask?.cancel()
            controller.stop()
        }
        .onChange(of: controller.isPlaying) { _, playing in
            if playing { scheduleHide() } else { controlsVisible = true }
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(request.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("VLC")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.white.opacity(0.2), in: Capsule())
            }
            .padding()

            Spacer()

            VStack(spacing: 12) {
                HStack(spacing: 28) {
                    if controller.isSeekable {
                        Button { controller.jump(seconds: -10) } label: {
                            Image(systemName: "gobackward.10").font(.title2)
                        }
                    }
                    Button { controller.togglePlayPause() } label: {
                        Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                            .font(.largeTitle)
                    }
                    if controller.isSeekable {
                        Button { controller.jump(seconds: 10) } label: {
                            Image(systemName: "goforward.10").font(.title2)
                        }
                    }
                }
                .buttonStyle(.plain)

                HStack {
                    Text(controller.elapsedText).font(.caption.monospacedDigit())
                    #if !os(tvOS)
                    if controller.isSeekable {
                        Slider(
                            value: Binding(
                                get: { controller.position },
                                set: { controller.seek(to: $0) }
                            ),
                            in: 0...1
                        )
                        .tint(Theme.accent)
                    } else {
                        Spacer()
                    }
                    #else
                    Spacer()
                    #endif
                    Text(controller.remainingText).font(.caption.monospacedDigit())
                }
            }
            .padding()
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            )
        }
        .foregroundStyle(.white)
        .transition(.opacity)
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Playback failed").font(.headline)
            Text(message).font(.subheadline).multilineTextAlignment(.center)
            Text(request.url.absoluteString)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(4)
            Button("Close") { dismiss() }
        }
        .padding(24)
        .frame(maxWidth: 600)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.white)
    }

    private func toggleControls() {
        withAnimation { controlsVisible.toggle() }
        if controlsVisible { scheduleHide() }
    }

    /// Hides the controls a few seconds after they appear while playing.
    private func scheduleHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, controller.isPlaying else { return }
            withAnimation { controlsVisible = false }
        }
    }
}
