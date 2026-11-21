import SwiftUI

struct PosterCard: View {
    @EnvironmentObject private var store: AppStore
    let item: MediaItem
    /// Watched fraction, shown as a bar over the bottom of the poster.
    var progress: Double?
    /// Second caption line, e.g. the episode being watched ("S1 E3").
    var subtitle: String?
    var width: CGFloat = Theme.posterWidth
    /// The name under the poster (the grids); Home's rows show the artwork alone, as Netflix does.
    var showsTitle = true

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
            if showsTitle {
                Text(item.name)
                    .font(Self.titleFont)
                    .lineLimit(1)
                    .foregroundStyle(Self.titleColor)
                    .frame(width: width, alignment: .leading)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
                    .frame(width: width, alignment: .leading)
            }
        }
    }

    private var poster: some View {
        RemoteImage(url: item.posterURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            placeholder
        }
        .frame(width: width, height: width / Theme.posterAspect)
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

/// A titled shelf of posters. Netflix-style: the artwork alone, no captions (channels keep their names), and a
/// "See All" header that opens the whole list where there is one.
struct MediaRow: View {
    let title: String
    let items: [MediaItem]
    var posterWidth: CGFloat = Theme.posterWidth
    /// Captions under the posters; channels always keep theirs (a logo alone doesn't say much).
    var showsTitles = false
    /// Numbers the posters 1, 2, 3… in large digits (Top 10).
    var isRanked = false
    var onSeeAll: (() -> Void)?
    let onSelect: (MediaItem) -> Void

    #if os(tvOS)
    @Environment(\.lockupFocusAction) private var focusAction
    @FocusState private var focusedID: String?
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RowHeader(title: title, onSeeAll: onSeeAll)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: isRanked ? LockupMetrics.rowSpacing * 0.6 : LockupMetrics.rowSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button { onSelect(item) } label: {
                            if isRanked {
                                RankedPosterCard(rank: index + 1, item: item, width: posterWidth)
                            } else {
                                PosterCard(item: item, width: posterWidth, showsTitle: showsTitles || item.kind == .live)
                            }
                        }
                        .lockupButtonStyle()
                        .favoriteContextMenu(item)
                        #if os(tvOS)
                        .focused($focusedID, equals: item.id)
                        #endif
                    }
                }
                .padding(.horizontal)
                #if os(tvOS)
                .padding(.vertical, 40)
                #endif
            }
            .scrollClipDisabled()
        }
        #if os(tvOS)
        .onChange(of: focusedID) { _, id in
            if let id, let item = items.first(where: { $0.id == id }) { focusAction?(item) }
        }
        #endif
    }
}

/// A row's title; with a destination, a button ending in a chevron (not on Apple TV, where headers
/// aren't focusable).
struct RowHeader: View {
    let title: String
    var onSeeAll: (() -> Void)?

    private var label: some View {
        Text(title)
            .font(.title3.weight(.bold))
            .lineLimit(1)
    }

    var body: some View {
        Group {
            #if os(tvOS)
            label
            #else
            if let onSeeAll {
                Button(action: onSeeAll) {
                    HStack(spacing: 6) {
                        label
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("See All")
            } else {
                label
            }
            #endif
        }
        .padding(.horizontal)
    }
}

/// Movies and series being watched, with their progress; hidden when empty.
struct ContinueWatchingRow: View {
    let entries: [ContinueWatchingEntry]
    var posterWidth: CGFloat = Theme.posterWidth
    let onSelect: (MediaItem) -> Void

    #if os(tvOS)
    @Environment(\.lockupFocusAction) private var focusAction
    @FocusState private var focusedID: String?
    #endif

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                RowHeader(title: String(localized: "Continue Watching"))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: LockupMetrics.rowSpacing) {
                        ForEach(entries) { entry in
                            Button { onSelect(entry.item) } label: {
                                PosterCard(item: entry.item, progress: entry.progress.fraction,
                                           subtitle: entry.progress.episodeLabel, width: posterWidth, showsTitle: false)
                            }
                            .lockupButtonStyle()
                            .favoriteContextMenu(entry.item, inContinueWatching: true)
                            #if os(tvOS)
                            .focused($focusedID, equals: entry.item.id)
                            #endif
                        }
                    }
                    .padding(.horizontal)
                    #if os(tvOS)
                    .padding(.vertical, 40)
                    #endif
                }
                .scrollClipDisabled()
            }
            #if os(tvOS)
            .onChange(of: focusedID) { _, id in
                if let id, let entry = entries.first(where: { $0.item.id == id }) { focusAction?(entry.item) }
            }
            #endif
        }
    }
}

#if os(tvOS)
/// Called with the poster that takes the focus in Home's rows, for the billboard above them.
struct LockupFocusAction {
    let action: (MediaItem) -> Void
    func callAsFunction(_ item: MediaItem) { action(item) }
}

private struct LockupFocusActionKey: EnvironmentKey {
    static let defaultValue: LockupFocusAction? = nil
}

extension EnvironmentValues {
    var lockupFocusAction: LockupFocusAction? {
        get { self[LockupFocusActionKey.self] }
        set { self[LockupFocusActionKey.self] = newValue }
    }
}
#endif

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
