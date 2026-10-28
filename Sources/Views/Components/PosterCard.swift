import SwiftUI

struct PosterCard: View {
    let item: MediaItem
    /// Watched fraction, shown as a bar over the bottom of the poster.
    var progress: Double?
    /// Second caption line, e.g. the episode being watched ("S1 E3").
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            poster
                .overlay(alignment: .bottom) {
                    if let progress {
                        WatchProgressBar(fraction: progress)
                            .clipShape(UnevenRoundedRectangle(
                                bottomLeadingRadius: Theme.cardCornerRadius,
                                bottomTrailingRadius: Theme.cardCornerRadius
                            ))
                    }
                }
            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(Theme.textSecondary)
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
                LazyHStack(spacing: 14) {
                    ForEach(items) { item in
                        Button { onSelect(item) } label: {
                            PosterCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                #if os(tvOS)
                .padding(.vertical, 24)
                #endif
            }
        }
    }
}

/// Movies and series being watched, with their progress; hidden when empty.
struct ContinueWatchingRow: View {
    let entries: [AppStore.ContinueWatchingEntry]
    let onSelect: (MediaItem) -> Void

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Continue Watching")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(entries) { entry in
                            Button { onSelect(entry.item) } label: {
                                PosterCard(item: entry.item, progress: entry.progress.fraction,
                                           subtitle: entry.progress.episodeLabel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    #if os(tvOS)
                    .padding(.vertical, 24)
                    #endif
                }
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
