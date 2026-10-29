import SwiftUI

/// What plays, shown with the player controls: the channel and the programme on now (kept current by the
/// minute), the series and the episode, or the movie's title.
struct NowPlayingInfo: View {
    @EnvironmentObject private var guide: EPGStore
    let request: PlaybackRequest

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(request.channel?.name ?? request.title)
                    .font(Self.titleFont)
                    .lineLimit(1)
                if let channel = request.channel {
                    if let now = guide.current(for: channel, at: context.date) {
                        programme(now)
                    }
                } else if let subtitle = request.subtitle {
                    Text(subtitle)
                        .font(Self.detailFont)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.6), radius: 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func programme(_ entry: EPGEntry) -> some View {
        HStack(spacing: 8) {
            Text("NOW")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Theme.accent)
            Text(entry.title)
                .lineLimit(1)
            Text(entry.start, style: .time) + Text(verbatim: " – ") + Text(entry.end, style: .time)
        }
        .font(Self.detailFont)
        .foregroundStyle(.white.opacity(0.85))
    }

    #if os(tvOS)
    private static let titleFont = Font.title3.weight(.semibold)
    private static let detailFont = Font.callout
    #else
    private static let titleFont = Font.headline
    private static let detailFont = Font.subheadline
    #endif
}
