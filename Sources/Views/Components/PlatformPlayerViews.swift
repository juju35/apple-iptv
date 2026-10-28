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

    /// Embeds `AVPlayerViewController` (not meant to be subclassed) to re-attach the player when
    /// the view appears again: after an iPhone Duo layout switch or a move to the other screen the
    /// picture can otherwise stay black while the sound goes on.
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

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            reattachPlayer()
        }

        override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.reattachPlayer() }
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
