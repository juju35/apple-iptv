#if os(iOS)
import SwiftUI

/// The player's iPhone Duo fold layout for the screenshots (`-demoScreen player`): a still instead of a stream,
/// controls as during playback.
@available(iOS 27.1, *)
struct DemoPlayerView: View {
    private let title = "The Long Horizon"

    var body: some View {
        FoldAwarePlayerLayout {
            still
        } controls: {
            FoldControlsPanel(
                title: title,
                isPlaying: true,
                isSeekable: true,
                position: .constant(0.38),
                elapsed: "41:12",
                remaining: "-1:06:48",
                onPlayPause: {},
                onSkip: { _ in },
                onClose: {}
            )
        } flat: {
            still.ignoresSafeArea()
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var still: some View {
        GeneratedArtwork(title: title, kind: .movie)
    }
}
#endif
