#if os(tvOS)
import SwiftUI

/// Apple TV transport for the VLC engine, modelled on the system player's: what plays (channel and programme,
/// series and episode, or movie), progress bar with elapsed and
/// remaining time at the bottom, driven from the remote rather than on-screen buttons.
///
/// - Select or Play/Pause: pause / resume (and show the bar)
/// - Left / right: back / forward 10 seconds
/// - Up / down: previous / next channel when zapping through a list, else show the bar
/// - Menu: hide the bar, or leave the player when it's hidden or paused
struct TVTransportOverlay: View {
    let controller: VLCPlayerController
    let request: PlaybackRequest
    let switcher: ChannelSwitcher?
    let onClose: () -> Void

    @State private var isVisible = true
    @State private var hideTask: Task<Void, Never>?
    /// "−10" / "+10" flashed in the middle after a skip.
    @State private var skip: Int?
    @State private var skipTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            // Takes the focus, hence the remote's presses, over the whole screen.
            Color.clear

            if isVisible {
                bar.transition(.opacity)
            }

            if let skip {
                skipBadge(skip)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .focusable()
        .focused($isFocused)
        .onAppear {
            isFocused = true
            scheduleHide()
        }
        .onDisappear {
            hideTask?.cancel()
            skipTask?.cancel()
        }
        .onPlayPauseCommand { togglePlayback() }
        .onTapGesture { togglePlayback() }
        .onMoveCommand(perform: move)
        .onExitCommand {
            if isVisible && controller.isPlaying {
                withAnimation { isVisible = false }
            } else {
                onClose()
            }
        }
        .onChange(of: controller.isPlaying) { _, playing in
            if playing { scheduleHide() } else { show() }
        }
        .animation(.easeOut(duration: 0.25), value: isVisible)
        .animation(.easeOut(duration: 0.2), value: skip)
    }

    // MARK: Bar

    private var bar: some View {
        VStack(alignment: .leading, spacing: 22) {
            NowPlayingInfo(request: request)

            if controller.isSeekable {
                ProgressTrack(fraction: Double(controller.position))
                HStack {
                    Label(controller.elapsedText,
                          systemImage: controller.isPlaying ? "play.fill" : "pause.fill")
                    Spacer()
                    Text(controller.remainingText)
                }
                .font(.callout.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
            } else {
                HStack(spacing: 24) {
                    Label("LIVE", systemImage: "circle.fill")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(Theme.accent)
                    if !controller.isPlaying {
                        Image(systemName: "pause.fill")
                    }
                    if switcher != nil {
                        Label("Channels", systemImage: "chevron.up.chevron.down")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 90)
        .padding(.top, 160)
        .padding(.bottom, 70)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
        )
    }

    private func skipBadge(_ seconds: Int) -> some View {
        Image(systemName: seconds < 0 ? "gobackward.10" : "goforward.10")
            .font(.system(size: 64, weight: .semibold))
            .foregroundStyle(.white)
            .padding(40)
            .background(.ultraThinMaterial, in: Circle())
    }

    // MARK: Remote

    private func move(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            jump(-10)
        case .right:
            jump(10)
        case .up:
            if let switcher { switcher.previous() } else { show() }
        case .down:
            if let switcher { switcher.next() } else { show() }
        @unknown default:
            show()
        }
    }

    private func togglePlayback() {
        controller.togglePlayPause()
        show()
    }

    private func jump(_ seconds: Int) {
        guard controller.isSeekable else {
            show()
            return
        }
        controller.jump(seconds: Int32(seconds))
        skip = seconds
        skipTask?.cancel()
        skipTask = Task {
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            skip = nil
        }
        show()
    }

    private func show() {
        isVisible = true
        scheduleHide()
    }

    /// Hides the bar a few seconds after the last press while playing; it stays while paused.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, controller.isPlaying else { return }
            isVisible = false
        }
    }
}

/// The system player's thin progress capsule with a playhead.
private struct ProgressTrack: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white)
                    .frame(width: proxy.size.width * clamped)
                Circle().fill(.white)
                    .frame(width: 22, height: 22)
                    .shadow(radius: 4)
                    .offset(x: proxy.size.width * clamped - 11)
            }
        }
        .frame(height: 10)
    }
}
#endif
