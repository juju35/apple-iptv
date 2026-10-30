import SwiftUI

/// The scrolling list of channels. Its own view so that, on Apple TV, a focus move only re-renders the
/// list, not the whole Live TV screen (sidebar and programme panel included).
struct ChannelList: View {
    let channels: [MediaItem]
    /// The channel shown in the info panel, marked in the list (large screens).
    let highlightedID: String?
    let onSelect: (MediaItem) -> Void
    /// Apple TV: the channel the focus rests on, once it stops moving.
    var onFocusRest: (MediaItem) -> Void = { _ in } // swiftlint:disable:this unused_declaration

    var body: some View {
        #if os(tvOS)
        // A UIKit collection view: SwiftUI's lazy stack crawled through hundreds of channels on Apple TV.
        TVChannelList(channels: channels, highlightedID: highlightedID, onSelect: onSelect, onFocusRest: onFocusRest)
        #else
        list
        #endif
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(channels) { channel in
                    Button {
                        onSelect(channel)
                    } label: {
                        ChannelRow(channel: channel, isHighlighted: channel.id == highlightedID)
                    }
                    .rowButtonStyle()
                    .favoriteContextMenu(channel)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }
}
