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

    private var statusObservation: NSKeyValueObservation?
    private var playerStatusObservation: NSKeyValueObservation?
    private var failureObserver: (any NSObjectProtocol)?

    func start(_ request: PlaybackRequest) {
        #if os(iOS)
        // Activating the session synchronously on the main thread is flagged as a hang risk; do it off-main.
        Task.detached(priority: .userInitiated) {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        #endif

        var options: [String: Any] = [:]
        if let userAgent = request.headers["User-Agent"] {
            options[AVURLAssetHTTPUserAgentKey] = userAgent
        }
        let asset = AVURLAsset(url: request.url, options: options)
        let item = AVPlayerItem(asset: asset)
        #if !os(macOS)
        // Shows the title in the system player chrome / Now Playing; unavailable on macOS.
        item.externalMetadata = [Self.metadataItem(.commonIdentifierTitle, value: request.title)]
        #endif

        // Observe before attaching to the player: attaching is what starts loading.
        statusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            let status = item.status
            let error = item.error
            Task { @MainActor [weak self] in
                switch status {
                case .readyToPlay:
                    self?.isReady = true
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
        guard let error else { return "Unknown playback error." }
        let nsError = error as NSError
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        var parts = [error.localizedDescription, "\((underlying ?? nsError).domain) \((underlying ?? nsError).code)"]

        // Look for a known-unsupported container in the path or in query values (Stalker uses `stream=123.mkv`).
        var candidates = [url.pathExtension.lowercased()]
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            candidates += items.compactMap { $0.value?.components(separatedBy: ".").last?.lowercased() }
        }
        if let container = candidates.first(where: { unsupportedContainers.contains($0) }) {
            parts.append("The system player can't play .\(container) files; only MP4/MOV and HLS streams are supported.")
        } else if nsError.domain == AVFoundationErrorDomain,
                  nsError.code == AVError.Code.fileFormatNotRecognized.rawValue {
            parts.append("This container isn't supported by the system player.")
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

/// Full-screen player shared by iOS, macOS and tvOS.
/// On iPhone Duo (iOS 27.1+), half-folding the device switches to a
/// Netflix-style laptop layout: video above the fold, controls below.
struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let request: PlaybackRequest

    @State private var controller = PlayerController()

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let player = controller.player {
                #if os(iOS)
                if #available(iOS 27.1, *) {
                    FoldAwarePlayerView(player: player, title: request.title) { dismiss() }
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
        .onAppear { controller.start(request) }
        .onDisappear { controller.stop() }
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

/// System VideoPlayer with a close button (non-tvOS).
struct StandardPlayerView: View {
    let player: AVPlayer
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            VideoPlayer(player: player)
                .ignoresSafeArea()

            #if !os(tvOS)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding()
            }
            .buttonStyle(.plain)
            #endif
        }
    }
}
