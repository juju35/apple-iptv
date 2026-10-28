import SwiftUI

/// Channel zapping offered to the players while a live channel plays from a list.
struct ChannelSwitcher {
    let channelName: String
    let previous: () -> Void
    let next: () -> Void
    let toggleList: () -> Void
}

extension EnvironmentValues {
    /// Set by `PlayerView` when the playing channel belongs to a list of several channels.
    @Entry var channelSwitcher: ChannelSwitcher?
}

/// Previous / next channel and channel list buttons, with the channel name, for the player controls.
/// On the Mac, ⌘↑ / ⌘↓ switch channels.
struct ChannelSwitchBar: View {
    @Environment(\.channelSwitcher) private var switcher

    var body: some View {
        if let switcher {
            HStack(spacing: 14) {
                Button(action: switcher.previous) {
                    Image(systemName: "chevron.up")
                }
                .commandShortcut(.upArrow)
                .accessibilityLabel("Previous channel")

                Text(switcher.channelName)
                    .font(.headline)
                    .lineLimit(1)

                Button(action: switcher.next) {
                    Image(systemName: "chevron.down")
                }
                .commandShortcut(.downArrow)
                .accessibilityLabel("Next channel")

                Button(action: switcher.toggleList) {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("Channel list")
            }
            .font(.title3.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

/// Channels of the list being watched, over the side of the player; picking one switches to it.
struct ChannelListPanel: View {
    let channels: [MediaItem]
    let current: MediaItem?
    let onSelect: (MediaItem) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Channels").font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close channel list")
            }
            .padding()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(channels) { channel in
                            Button { onSelect(channel) } label: {
                                ChannelRow(channel: channel, isHighlighted: channel.id == current?.id)
                            }
                            .buttonStyle(.plain)
                            .id(channel.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .onAppear {
                    if let current { proxy.scrollTo(current.id, anchor: .center) }
                }
            }
        }
        .frame(width: Theme.channelListMinWidth + 40)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .foregroundStyle(.white)
    }
}

private extension View {
    /// ⌘ + `key`, where keyboards exist (not on tvOS).
    @ViewBuilder
    func commandShortcut(_ key: KeyEquivalent) -> some View {
        #if os(tvOS)
        self
        #else
        keyboardShortcut(key, modifiers: .command)
        #endif
    }
}
