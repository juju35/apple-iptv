import SwiftUI
import AVKit
import Observation

/// Owns the AVPlayer and reports loading failures so they are visible to the user.
@MainActor
@Observable
final class PlayerController {
    private(set) var player: AVPlayer?
    private(set) var errorMessage: String?
    private(set) var isReady = false

    /// Current position and duration in seconds, for saving watch progress.
    var progressSample: (position: Double, duration: Double)? {
        guard let player, let item = player.currentItem else { return nil }
        return (player.currentTime().seconds, item.duration.seconds)
    }

    private var pendingSeek: Double = 0
    private var statusObservation: NSKeyValueObservation?
    private var playerStatusObservation: NSKeyValueObservation?
    private var failureObserver: (any NSObjectProtocol)?

    /// `subtitle`: the episode, or the programme on now for a live channel (AVKit's second title line).
    func start(_ request: PlaybackRequest, subtitle: String? = nil) {
        #if os(iOS)
        // Activating the session synchronously on the main thread is flagged as a hang risk; do it off-main.
        Task.detached(priority: .userInitiated) {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        #endif

        pendingSeek = request.startPosition
        var options: [String: Any] = [:]
        if let userAgent = request.headers["User-Agent"] {
            options[AVURLAssetHTTPUserAgentKey] = userAgent
        }
        let asset = AVURLAsset(url: request.url, options: options)
        let item = AVPlayerItem(asset: asset)
        #if !os(macOS)
        // Shows the title in the system player chrome / Now Playing; unavailable on macOS.
        var metadata = [Self.metadataItem(.commonIdentifierTitle, value: request.title)]
        if let subtitle {
            metadata.append(Self.metadataItem(.iTunesMetadataTrackSubTitle, value: subtitle))
        }
        item.externalMetadata = metadata
        #endif

        // Observe before attaching to the player: attaching is what starts loading.
        statusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            let status = item.status
            let error = item.error
            Task { @MainActor [weak self] in
                switch status {
                case .readyToPlay:
                    self?.isReady = true
                    self?.resumeIfNeeded()
                case .failed:
                    self?.errorMessage = Self.describe(error, url: request.url)
                default:
                    break
                }
            }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self] in
                self?.errorMessage = Self.describe(error, url: request.url)
            }
        }

        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        playerStatusObservation = player.observe(\.status, options: [.new]) { [weak self] player, _ in
            guard player.status == .failed else { return }
            let error = player.error
            Task { @MainActor [weak self] in
                self?.errorMessage = Self.describe(error, url: request.url)
            }
        }
        self.player = player
        print("[Player] playing \(request.url.absoluteString)")
        player.play()
    }

    /// Jumps to the saved position once the item can seek.
    private func resumeIfNeeded() {
        guard pendingSeek > 0, let player else { return }
        let time = CMTime(seconds: pendingSeek, preferredTimescale: 600)
        pendingSeek = 0
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
    }

    func stop() {
        player?.pause()
        statusObservation = nil
        playerStatusObservation = nil
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
        failureObserver = nil
        player = nil
    }

    /// Containers AVFoundation cannot demux; they need a third-party engine (VLCKit, KSPlayer…).
    private static let unsupportedContainers: Set<String> = ["mkv", "avi", "wmv", "flv", "ts", "mpg", "mpeg", "webm", "ogm", "divx"]

    private static func describe(_ error: Error?, url: URL) -> String {
        guard let error else { return String(localized: "Unknown playback error.") }
        let nsError = error as NSError
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        var parts = [error.localizedDescription, "\((underlying ?? nsError).domain) \((underlying ?? nsError).code)"]

        // Look for a known-unsupported container in the path or in query values (Stalker uses `stream=123.mkv`).
        var candidates = [url.pathExtension.lowercased()]
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            candidates += items.compactMap { $0.value?.components(separatedBy: ".").last?.lowercased() }
        }
        if let container = candidates.first(where: { unsupportedContainers.contains($0) }) {
            parts.append(String(localized: """
                The system player can't play .\(container) files; only MP4/MOV and HLS streams are supported.
                """))
        } else if nsError.domain == AVFoundationErrorDomain,
                  nsError.code == AVError.Code.fileFormatNotRecognized.rawValue {
            parts.append(String(localized: "This container isn't supported by the system player."))
        }
        return parts.joined(separator: " · ")
    }

    private static func metadataItem(_ identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item
    }
}

/// Full-screen player shared by iOS, macOS and tvOS. Starts with the engine chosen for the
/// request and falls back to VLC when the system player can't open the stream.
struct PlayerView: View {
    #if os(macOS)
    @Environment(\.closePlayer) private var closePlayer
    #endif
    @EnvironmentObject private var store: AppStore

    /// Replaced when zapping to another channel.
    @State private var request: PlaybackRequest
    @State private var engine: PlaybackEngine
    @State private var showsChannelList = false

    init(request: PlaybackRequest) {
        _request = State(initialValue: request)
        _engine = State(initialValue: request.engine)
    }

    var body: some View {
        Group {
            switch engine {
            case .system:
                SystemPlayerView(request: request) {
                    // AVFoundation gave up (unsupported container, HLS refused…): retry with VLC.
                    print("[Player] system engine failed, falling back to VLC")
                    engine = .vlc
                }
            case .vlc:
                VLCPlayerView(request: request)
            }
        }
        // A new request (zapping) restarts the player from scratch.
        .id(request.id)
        .environment(\.channelSwitcher, channelSwitcher)
        .overlay(alignment: .trailing) {
            if showsChannelList {
                ChannelListPanel(channels: request.channelList, current: request.channel,
                                 onSelect: { zap(to: $0) }, onClose: { showsChannelList = false })
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.2), value: showsChannelList)
        #if os(macOS)
        // Escape closes the window-overlay player, as it would a sheet.
        .onExitCommand { closePlayer?() }
        #endif
    }

    /// Zapping, when a live channel plays from a list of several.
    private var channelSwitcher: ChannelSwitcher? {
        guard let channel = request.channel, request.channelList.count > 1 else { return nil }
        return ChannelSwitcher(
            channelName: channel.name,
            previous: { zap(by: -1) },
            next: { zap(by: 1) },
            toggleList: { showsChannelList.toggle() }
        )
    }

    private func zap(by offset: Int) {
        let list = request.channelList
        guard let index = list.firstIndex(where: { $0.id == request.channel?.id }) else { return }
        zap(to: list[(index + offset + list.count) % list.count])
    }

    private func zap(to channel: MediaItem) {
        showsChannelList = false
        guard channel.id != request.channel?.id else { return }
        let list = request.channelList
        Task { @MainActor in
            guard var next = try? await store.playbackRequest(for: channel) else { return }
            next.channelList = list
            engine = next.engine
            request = next
        }
    }
}

extension EnvironmentValues {
    /// Opens the player over the whole window (macOS); nil where players are presented modally.
    @Entry var presentPlayer: PresentPlayerAction?
    /// Closes the window-overlay player; nil when the player is a sheet or full-screen cover.
    @Entry var closePlayer: ClosePlayerAction?
}

/// Equatable wrapper so re-setting the environment value doesn't invalidate readers on every update.
/// All instances compare equal: `MainTabView` always installs the same behavior (show the overlay player).
struct PresentPlayerAction: Equatable {
    let action: (PlaybackRequest) -> Void

    func callAsFunction(_ request: PlaybackRequest) { action(request) }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

/// Equatable wrapper so re-setting the environment value doesn't invalidate readers on every update.
/// All instances compare equal: `MainTabView` always installs the same behavior (dismiss the overlay player).
struct ClosePlayerAction: Equatable {
    let action: () -> Void

    func callAsFunction() { action() }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

/// AVFoundation-backed player (HLS, MP4). Reports failures through `onFailure`.
/// On iPhone Duo (iOS 27.1+), half-folding the device switches to a
/// Netflix-style laptop layout: video above the fold, controls below.
struct SystemPlayerView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var guide: EPGStore
    @Environment(\.dismiss) private var dismissPresentation
    @Environment(\.closePlayer) private var closePlayer
    let request: PlaybackRequest
    let onFailure: () -> Void

    @State private var controller = PlayerController()

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let player = controller.player {
                #if os(iOS)
                if #available(iOS 27.1, *) {
                    FoldAwarePlayerView(player: player, title: request.title, artworkURL: request.artworkURL) {
                        dismiss()
                    }
                } else {
                    StandardPlayerView(player: player) { dismiss() }
                }
                #else
                StandardPlayerView(player: player) { dismiss() }
                #endif
            } else {
                #if !os(tvOS)
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding()
                }
                .buttonStyle(.plain)
                #endif
            }

            if let message = controller.errorMessage {
                errorOverlay(message)
            } else if !controller.isReady {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            let programme = request.channel.flatMap { guide.current(for: $0)?.title }
            controller.start(request, subtitle: programme ?? request.subtitle)
        }
        .task(id: controller.isReady) {
            guard controller.isReady else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                saveProgress()
            }
        }
        .onDisappear {
            saveProgress()
            controller.stop()
        }
        .onChange(of: controller.errorMessage) { _, message in
            if message != nil { onFailure() }
        }
    }

    /// Closes the player: the macOS window overlay's action, else the sheet / full-screen cover.
    private func dismiss() {
        if let closePlayer { closePlayer() } else { dismissPresentation() }
    }

    private func saveProgress() {
        guard let context = request.progress, let sample = controller.progressSample else { return }
        store.recordProgress(context, position: sample.position, duration: sample.duration)
    }

    /// The failing URL; selectable where the platform allows copying it (not on tvOS).
    private var urlText: some View {
        #if os(tvOS)
        Text(request.url.absoluteString)
        #else
        Text(request.url.absoluteString).textSelection(.enabled)
        #endif
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Playback failed").font(.headline)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            urlText
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(4)
            #if os(tvOS)
            Button("Close") { dismiss() }
            #endif
        }
        .padding(24)
        .frame(maxWidth: 600)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }
}

/// System video player. On macOS with our close button; on iOS AVKit shows its own (the player inherits the
/// full-screen presentation), so ours would be a second one. The close button / channel bar and the status bar /
/// home indicator (iOS) stay hidden during playback; a click or tap brings them back. On macOS the window's title
/// bar and tabs stay hidden for the whole playback.
struct StandardPlayerView: View {
    let player: AVPlayer
    let onClose: () -> Void

    #if !os(tvOS)
    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    #endif

    var body: some View {
        #if os(tvOS)
        VideoPlayer(player: player)
            .ignoresSafeArea()
        #else
        ZStack(alignment: .topLeading) {
            video

            if controlsVisible {
                #if os(macOS)
                closeButton
                #endif
                ChannelSwitchBar()
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear { scheduleHide() }
        .onDisappear { hideControlsTask?.cancel() }
        #if os(iOS)
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(controlsVisible ? .automatic : .hidden)
        #endif
        #endif
    }

    #if os(macOS)
    /// AppKit controls follow ours; a transparent layer catches the click while they're hidden.
    private var video: some View {
        ZStack {
            AppKitPlayerView(player: player, showsControls: controlsVisible)
                .ignoresSafeArea()
            if !controlsVisible {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { showControls() }
                    .ignoresSafeArea()
            }
        }
        .onContinuousHover { _ in
            if controlsVisible { scheduleHide() }
        }
    }
    #elseif os(iOS)
    /// The system controls toggle on tap; ours follow the same tap without stealing it.
    private var video: some View {
        UIKitPlayerView(player: player, onTap: {
            if controlsVisible {
                withAnimation { controlsVisible = false }
            } else {
                showControls()
            }
        }, onDismiss: onClose)
        .ignoresSafeArea()
    }
    #endif

    #if os(macOS)
    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.title)
                .foregroundStyle(.white.opacity(0.8))
                .padding()
        }
        .buttonStyle(.plain)
    }

    #endif

    #if !os(tvOS)
    private func showControls() {
        withAnimation { controlsVisible = true }
        scheduleHide()
    }

    /// Hides the controls after a few seconds without interaction, while playing.
    private func scheduleHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, player.timeControlStatus != .paused else { return }
            withAnimation { controlsVisible = false }
        }
    }
    #endif
}
