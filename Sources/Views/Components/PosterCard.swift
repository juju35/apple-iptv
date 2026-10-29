import SwiftUI

struct PosterCard: View {
    @EnvironmentObject private var store: AppStore
    let item: MediaItem
    /// Watched fraction, shown as a bar over the bottom of the poster.
    var progress: Double?
    /// Second caption line, e.g. the episode being watched ("S1 E3").
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            poster
                .overlay(alignment: .topLeading) {
                    if item.kind == .movie, store.isWatched(PlaybackProgressContext.movie(item).key) {
                        WatchedBadge().padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if store.isFavorite(item) {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                            .padding(5)
                            .background(.black.opacity(0.55), in: Circle())
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let progress {
                        WatchProgressBar(fraction: progress)
                            .clipShape(UnevenRoundedRectangle(
                                bottomLeadingRadius: Theme.cardCornerRadius,
                                bottomTrailingRadius: Theme.cardCornerRadius
                            ))
                    }
                }
                .lockupArtwork()
            Text(item.name)
                .font(Self.titleFont)
                .lineLimit(1)
                .foregroundStyle(Self.titleColor)
                .frame(width: Theme.posterWidth, alignment: .leading)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
        }
    }

    private var poster: some View {
        AsyncImage(url: item.posterURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                placeholder
            }
        }
        .frame(width: Theme.posterWidth, height: Theme.posterWidth / Theme.posterAspect)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .strokeBorder(.white.opacity(0.08))
        )
    }

    private var placeholder: some View {
        GeneratedArtwork(title: item.name, kind: item.kind)
    }

    // Read from the couch on Apple TV: larger and brighter than the phone's caption.
    #if os(tvOS)
    private static let titleFont = Font.callout.weight(.medium)
    private static let titleColor = Color.white.opacity(0.85)
    #else
    private static let titleFont = Font.caption
    private static let titleColor = Theme.textSecondary
    #endif
}

struct MediaRow: View {
    let title: String
    let items: [MediaItem]
    let onSelect: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: LockupMetrics.rowSpacing) {
                    ForEach(items) { item in
                        Button { onSelect(item) } label: {
                            PosterCard(item: item)
                        }
                        .lockupButtonStyle()
                        .favoriteContextMenu(item)
                    }
                }
                .padding(.horizontal)
                #if os(tvOS)
                .padding(.vertical, 40)
                #endif
            }
            .scrollClipDisabled()
        }
    }
}

/// Movies and series being watched, with their progress; hidden when empty.
struct ContinueWatchingRow: View {
    let entries: [ContinueWatchingEntry]
    let onSelect: (MediaItem) -> Void

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Continue Watching")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: LockupMetrics.rowSpacing) {
                        ForEach(entries) { entry in
                            Button { onSelect(entry.item) } label: {
                                PosterCard(item: entry.item, progress: entry.progress.fraction,
                                           subtitle: entry.progress.episodeLabel)
                            }
                            .lockupButtonStyle()
                            .favoriteContextMenu(entry.item, inContinueWatching: true)
                        }
                    }
                    .padding(.horizontal)
                    #if os(tvOS)
                    .padding(.vertical, 40)
                    #endif
                }
                .scrollClipDisabled()
            }
        }
    }
}

/// Thin red bar showing how much of a video was watched.
struct WatchProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(.black.opacity(0.55))
                Rectangle().fill(Theme.accent)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
    }
}

/// Checkmark on movies and episodes watched to the end.
struct WatchedBadge: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.caption2.weight(.heavy))
            .foregroundStyle(.white)
            .padding(5)
            .background(Circle().fill(.green.opacity(0.85)))
            .accessibilityLabel("Watched")
    }
}
