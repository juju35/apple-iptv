import SwiftUI
import AVKit

#if os(macOS)
/// AppKit's player view. SwiftUI's `VideoPlayer` crashes on macOS with live streams: it builds its
/// scrubber range from the item duration, which is NaN (indefinite) for live HLS.
struct AppKitPlayerView: NSViewRepresentable {
    let player: AVPlayer
    let showsControls: Bool

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.showsFullScreenToggleButton = true
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
        let style: AVPlayerViewControlsStyle = showsControls ? .floating : .none
        if nsView.controlsStyle != style { nsView.controlsStyle = style }
    }
}
#endif

#if os(iOS)
/// `AVPlayerViewController` with a tap recognizer that runs alongside its own. SwiftUI's
/// `VideoPlayer` keeps taps to itself, so a SwiftUI gesture on it never fires.
struct UIKitPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIViewController(context: Context) -> PlayerHostController {
        let host = PlayerHostController()
        host.playerController.player = player
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        host.playerController.view.addGestureRecognizer(tap)
        return host
    }

    func updateUIViewController(_ host: PlayerHostController, context: Context) {
        if host.playerController.player !== player { host.playerController.player = player }
        context.coordinator.onTap = onTap
    }

    /// Embeds `AVPlayerViewController` (not meant to be subclassed) to re-attach the player after an
    /// iPhone Duo layout switch or a move to the other screen, where the picture can otherwise stay
    /// black while the sound goes on.
    final class PlayerHostController: UIViewController {
        let playerController = AVPlayerViewController()

        override func viewDidLoad() {
            super.viewDidLoad()
            addChild(playerController)
            playerController.view.frame = view.bounds
            playerController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(playerController.view)
            playerController.didMove(toParent: self)
        }

        /// Screen the player was last attached on.
        private weak var attachedScreen: UIScreen?
        private var hasAppeared = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // First appearance: a fresh surface after a layout switch. Later ones (back from AVKit's own
            // full screen, rotations) must not touch the player: detaching it mid-presentation leaves
            // AVKit's full-screen view without controls nor a way out.
            if !hasAppeared {
                hasAppeared = true
                attachedScreen = view.window?.windowScene?.screen
                reattachPlayer()
            } else {
                reattachIfScreenChanged()
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            reattachIfScreenChanged()
        }

        /// Moving to the other iPhone Duo screen can leave the picture black: attach the player again.
        private func reattachIfScreenChanged() {
            // Never while AVKit presents its own full screen.
            guard hasAppeared, presentedViewController == nil, playerController.presentedViewController == nil,
                  let screen = view.window?.windowScene?.screen, screen !== attachedScreen else { return }
            attachedScreen = screen
            reattachPlayer()
        }

        private func reattachPlayer() {
            guard let player = playerController.player else { return }
            playerController.player = nil
            playerController.player = player
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: () -> Void

        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }

        @objc func tapped() { onTap() }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#endif
