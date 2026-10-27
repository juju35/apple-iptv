import SwiftUI
import AVKit

/// Full-screen AVPlayer wrapper shared by iOS, macOS and tvOS.
struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let request: PlaybackRequest

    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            #if !os(tvOS)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding()
            }
            .buttonStyle(.plain)
            #endif
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    private func start() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let item = AVPlayerItem(url: request.url)
        item.externalMetadata = [metadataItem(.commonIdentifierTitle, value: request.title)]
        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        self.player = player
        player.play()
    }

    private func stop() {
        player?.pause()
        player = nil
    }

    private func metadataItem(_ identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item
    }
}
