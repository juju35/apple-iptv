import SwiftUI

/// Detail sheet: artwork, metadata, play button, episodes for series, EPG for live.
/// On Apple TV a full screen instead: artwork behind, title and actions low on the left, episodes below.
struct MediaDetailView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var guide: EPGStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentPlayer) private var presentPlayer
    let item: MediaItem

    @State private var detail: SeriesDetail?
    @State private var selectedSeason: Int?
    @State private var epg: [EPGEntry] = []
    @State private var playback: PlaybackRequest?
    @State private var loadError: String?
    @State private var isResolving = false

    var body: some View {
        #if os(tvOS)
        tvBody
            .task { await loadDetails() }
            .fullScreenCover(item: $playback) { request in
                PlayerView(request: request)
            }
        #else
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    primaryActions

                    if let plot = item.plot, !plot.isEmpty {
                        Text(plot).foregroundStyle(Theme.textSecondary)
                    }

                    if let loadError {
                        Label(loadError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }

                    if item.kind == .live, !epg.isEmpty {
                        epgSection
                    }

                    if item.kind == .series {
                        episodesSection
                    }
                }
                .padding()
            }
            .background { backdrop }
            .toolbar {
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
            }
            .task { await loadDetails() }
            .fullScreenCoverCompat(item: $playback) { request in
                PlayerView(request: request)
            }
        }
        .preferredColorScheme(.dark)
        #endif
    }

    /// Watch Live, Play / Resume + Start Over; a series' play button comes with its episodes.
    @ViewBuilder
    private var primaryActions: some View {
        switch item.kind {
        case .live:
            playButton(label: "Watch Live") {
                play(ref: item.playbackRef, ext: item.containerExtension)
            }
        case .movie:
            movieButtons
        case .series:
            EmptyView()
        }
    }

    #if os(tvOS)
    // MARK: - Apple TV

    private var tvBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 56) {
                VStack(alignment: .leading, spacing: 20) {
                    Text(item.name)
                        .font(.title.weight(.bold))
                        .lineLimit(2)
                    if !tvMetadata.isEmpty {
                        Text(tvMetadata)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    if let plot = item.plot, !plot.isEmpty {
                        Text(plot)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(4)
                    }
                    if let loadError {
                        Label(loadError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    HStack(spacing: 30) {
                        primaryActions
                        if item.kind == .series {
                            seriesPlayAction
                        }
                        favoriteButton
                    }
                    .padding(.top, 10)
                }
                .frame(maxWidth: 1100, alignment: .leading)
                // The first screen shows the artwork, with the title and actions low on the left.
                .frame(maxWidth: .infinity, minHeight: 640, alignment: .bottomLeading)

                if item.kind == .live, !epg.isEmpty {
                    epgSection
                }
                if item.kind == .series {
                    seasonEpisodes
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
        }
        .scrollClipDisabled()
        .background { tvBackdrop }
    }

    /// The artwork across the whole screen, softened and shaded from the left and the bottom for the text.
    private var tvBackdrop: some View {
        ZStack {
            Theme.background
            AsyncImage(url: item.posterURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill().blur(radius: 20)
                } else {
                    GeneratedArtwork(title: item.name, kind: item.kind, showsTitle: false)
                }
            }
            .opacity(0.7)
            LinearGradient(colors: [Theme.background.opacity(0.95), Theme.background.opacity(0.4), .clear],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.clear, Theme.background.opacity(0.85), Theme.background],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    /// "2025 · ★ 4.3 · Drama".
    private var tvMetadata: String {
        var parts: [String] = []
        if let year = item.year, !year.isEmpty { parts.append(year) }
        if let rating = item.rating, rating > 0 { parts.append("★ " + String(format: "%.1f", rating)) }
        parts.append(store.categoryName(item.categoryId, kind: item.kind))
        return parts.joined(separator: " · ")
    }
    #endif

    // MARK: - Sections

    /// The artwork, blurred and faded into the background, behind the whole sheet.
    private var backdrop: some View {
        ZStack {
            Theme.background
            AsyncImage(url: item.posterURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                        .blur(radius: 50)
                        .opacity(0.45)
                }
            }
            LinearGradient(colors: [.clear, Theme.background.opacity(0.7), Theme.background],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .clipped()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: item.posterURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    GeneratedArtwork(title: item.name, kind: item.kind)
                }
            }
            .frame(width: Theme.posterWidth, height: Theme.posterWidth / Theme.posterAspect)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))

            VStack(alignment: .leading, spacing: 8) {
                Text(item.name).font(.title2.weight(.bold))
                if let year = item.year, !year.isEmpty {
                    Text(year).foregroundStyle(Theme.textSecondary)
                }
                if let rating = item.rating, rating > 0 {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.subheadline)
                }
                Text(store.categoryName(item.categoryId, kind: item.kind))
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.surface, in: Capsule())
                favoriteButton
            }
            Spacer()
        }
    }

    private var favoriteButton: some View {
        let isFavorite = store.isFavorite(item)
        return Button {
            store.toggleFavorite(item)
        } label: {
            Label(isFavorite ? "In Favorites" : "Add to Favorites",
                  systemImage: isFavorite ? "heart.fill" : "heart")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isFavorite ? Theme.accent : .white)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
    }

    /// Play, or Resume + Start Over when the movie was started.
    @ViewBuilder
    private var movieButtons: some View {
        let context = PlaybackProgressContext.movie(item)
        if let saved = store.progress(for: context.key) {
            playButton(label: "Resume from \(Self.timeText(saved.position))") {
                play(ref: item.playbackRef, ext: item.containerExtension, progress: context,
                     from: saved.position)
            }
            startOverButton {
                play(ref: item.playbackRef, ext: item.containerExtension, progress: context)
            }
        } else {
            playButton(label: "Play") {
                play(ref: item.playbackRef, ext: item.containerExtension, progress: context)
            }
        }
    }

    private func startOverButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Start Over", systemImage: "arrow.counterclockwise")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: Self.actionMaxWidth)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .disabled(isResolving)
    }

    /// Full-width actions in the sheet; side by side, at their own size, on Apple TV.
    #if os(tvOS)
    private static let actionMaxWidth: CGFloat? = nil
    #else
    private static let actionMaxWidth: CGFloat? = .infinity
    #endif

    /// "1:02:03" or "12:34".
    private static func timeText(_ seconds: Double) -> String {
        let total = Int(seconds)
        let (hours, minutes, secs) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    private func playButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if isResolving {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.fill")
                }
                Text(isResolving ? "Loading…" : label)
            }
            .font(.headline)
            .frame(maxWidth: Self.actionMaxWidth)
            .padding(.vertical, 10)
        }
        .primaryActionStyle()
        .disabled(isResolving)
    }

    private var epgSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Program Guide").font(.headline)
            ForEach(epg.prefix(6)) { entry in
                HStack(alignment: .top) {
                    Text(entry.start, style: .time)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 54, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).font(.subheadline)
                        if let desc = entry.description, !desc.isEmpty {
                            Text(desc).font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var episodesSection: some View {
        seriesPlayAction
        seasonEpisodes
    }

    /// The season shown: picked by the user, else the one being watched, else the first.
    private func shownSeason(in detail: SeriesDetail) -> Int? {
        guard let first = detail.seasons.keys.min() else { return nil }
        return selectedSeason ?? resumedEpisode(in: detail)?.episode.season ?? first
    }

    /// Resume the episode being watched, else play the first one of the season shown.
    @ViewBuilder
    private var seriesPlayAction: some View {
        if let detail, let season = shownSeason(in: detail) {
            if let resumed = resumedEpisode(in: detail) {
                playButton(label: "Resume S\(resumed.episode.season) E\(resumed.episode.episode)"
                           + " · \(Self.timeText(resumed.progress.position))") {
                    playEpisode(resumed.episode)
                }
            } else if let first = detail.seasons[season]?.first {
                playButton(label: "Play S\(season) E\(first.episode)") {
                    playEpisode(first)
                }
            }
        } else if detail != nil {
            playButton(label: "Play") {
                play(ref: item.playbackRef, ext: item.containerExtension)
            }
        }
    }

    @ViewBuilder
    private var seasonEpisodes: some View {
        if let detail, let season = shownSeason(in: detail) {
            SeasonEpisodesView(
                detail: detail,
                season: Binding(get: { season }, set: { selectedSeason = $0 }),
                fallbackArtwork: item.posterURL,
                progress: { store.progress(for: PlaybackProgressContext.episode($0, of: item).key)?.fraction },
                isWatched: { store.isWatched(PlaybackProgressContext.episode($0, of: item).key) },
                onPlay: playEpisode
            )
        } else if detail == nil {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    // MARK: - Actions

    private func loadDetails() async {
        guard let provider = store.selectedProvider else { return }
        let client = store.client(for: provider)
        if item.kind == .series {
            detail = try? await client.seriesDetail(for: item)
        }
        if item.kind == .live {
            let cached = guide.entries(for: item).filter { $0.end > Date() }
            epg = cached.isEmpty ? ((try? await client.shortEPG(forChannelRef: item.playbackRef)) ?? []) : cached
        }
    }

    /// The most recently watched, unfinished episode, if it is still in the series.
    private func resumedEpisode(in detail: SeriesDetail) -> (episode: Episode, progress: PlaybackProgress)? {
        guard let saved = store.latestEpisodeProgress(forSeries: item.id),
              let episode = detail.seasons.values.joined().first(where: { $0.id == saved.episodeId }) else {
            return nil
        }
        return (episode, saved)
    }

    /// Plays an episode, resuming where it was left.
    private func playEpisode(_ episode: Episode) {
        let context = PlaybackProgressContext.episode(episode, of: item)
        play(ref: episode.playbackRef, ext: episode.containerExtension, progress: context,
             from: store.progress(for: context.key)?.position ?? 0, artwork: episode.posterURL)
    }

    private func play(ref: String, ext: String?, progress: PlaybackProgressContext? = nil, from start: Double = 0,
                      artwork: URL? = nil) {
        guard !isResolving else { return }
        isResolving = true
        loadError = nil
        // Stay on the main actor: `playback` and `loadError` drive the UI.
        Task { @MainActor in
            defer { isResolving = false }
            do {
                var request = try await store.playbackRequest(for: item, ref: ref, containerExtension: ext,
                                                              progress: progress, from: start)
                if let artwork { request.artworkURL = artwork }
                if item.kind == .live {
                    // Zap through the channel's list.
                    request.channelList = store.liveItems.filter { channel in
                        item.categoryId.map(channel.belongs(to:)) ?? (channel.categoryId == nil)
                    }
                }
                if let presentPlayer {
                    // macOS: close this sheet so the window-sized player isn't hidden behind it.
                    dismiss()
                    presentPlayer(request)
                } else {
                    playback = request
                }
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}

extension View {
    @ViewBuilder
    func fullScreenCoverCompat<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(macOS)
        self.sheet(item: item, content: content)
        #else
        self.fullScreenCover(item: item, content: content)
        #endif
    }
}
