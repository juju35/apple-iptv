import SwiftUI

/// The scrolling list of channels. Its own view so that, on Apple TV, a focus move only re-renders the
/// list, not the whole Live TV screen (sidebar and programme panel included).
struct ChannelList: View {
    let channels: [MediaItem]
    /// The channel shown in the info panel, marked in the list (large screens).
    let highlightedID: String?
    let onSelect: (MediaItem) -> Void
    /// Apple TV: the channel the focus rests on, once it stops moving.
    var onFocusRest: (MediaItem) -> Void = { _ in }

    #if os(tvOS)
    @FocusState private var focusedID: String?
    #endif

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(channels) { channel in
                    Button {
                        onSelect(channel)
                    } label: {
                        ChannelRow(channel: channel, isHighlighted: channel.id == highlightedID)
                    }
                    .rowButtonStyle()
                    #if os(tvOS)
                    .focused($focusedID, equals: channel.id)
                    #endif
                    .favoriteContextMenu(channel)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        #if os(tvOS)
        .scrollClipDisabled()
        // Once the focus rests: updating the programme panel on every step of a fast scroll was costly.
        .task(id: focusedID) {
            guard let id = focusedID, id != highlightedID else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let channel = channels.first(where: { $0.id == id }) else { return }
            onFocusRest(channel)
        }
        #endif
    }
}
