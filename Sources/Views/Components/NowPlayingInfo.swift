import SwiftUI

/// What plays, shown with the player controls: the channel with the programme on now (title, time slot,
/// progress, summary) and the next one, kept current by the minute; the series and the episode, or the
/// movie's title.
struct NowPlayingInfo: View {
    @EnvironmentObject private var guide: EPGStore
    let request: PlaybackRequest

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(request.channel?.name ?? request.title)
                    .font(Self.titleFont)
                    .lineLimit(1)
                if let channel = request.channel {
                    let now = guide.current(for: channel, at: context.date)
                    if let now {
                        programme(now, at: context.date)
                    }
                    if let next = guide.next(for: channel, at: now?.end ?? context.date) {
                        upcoming(next)
                    }
                } else if let subtitle = request.subtitle {
                    Text(subtitle)
                        .font(Self.detailFont)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            // Fetches the channel's short guide when the whole one has nothing on now, again once a
            // programme ends, and for the new channel after a channel switch.
            .task(id: refreshKey(at: context.date)) {
                if let channel = request.channel { await guide.loadShortIfNeeded(for: channel) }
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.6), radius: 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshKey(at date: Date) -> String {
        guard let channel = request.channel else { return request.title }
        return "\(channel.id)-\(guide.current(for: channel, at: date)?.id ?? "none")"
    }

    private func programme(_ entry: EPGEntry, at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("NOW")
                    .font(Self.badgeFont)
                    .foregroundStyle(Theme.accent)
                Text(entry.title)
                    .font(Self.programmeFont)
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                Text(entry.start, style: .time)
                WatchProgressBar(fraction: entry.progress(at: date))
                    .frame(maxWidth: Self.progressWidth)
                    .clipShape(Capsule())
                Text(entry.end, style: .time)
            }
            .font(Self.timeFont)
            .foregroundStyle(.white.opacity(0.75))
            if let description = entry.description, !description.isEmpty {
                Text(description)
                    .font(Self.detailFont)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
        }
    }

    private func upcoming(_ entry: EPGEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("NEXT")
                .font(Self.badgeFont)
                .foregroundStyle(.white.opacity(0.6))
            Text(entry.start, style: .time)
                .font(Self.timeFont)
            Text(entry.title)
                .lineLimit(1)
        }
        .font(Self.detailFont)
        .foregroundStyle(.white.opacity(0.75))
    }

    #if os(tvOS)
    private static let titleFont = Font.title3.weight(.semibold)
    private static let programmeFont = Font.headline
    private static let detailFont = Font.callout
    private static let timeFont = Font.callout.monospacedDigit()
    private static let badgeFont = Font.caption.weight(.heavy)
    private static let progressWidth: CGFloat = 360
    #else
    private static let titleFont = Font.headline
    private static let programmeFont = Font.subheadline.weight(.semibold)
    private static let detailFont = Font.subheadline
    private static let timeFont = Font.caption.monospacedDigit()
    private static let badgeFont = Font.caption2.weight(.heavy)
    private static let progressWidth: CGFloat = 220
    #endif
}
