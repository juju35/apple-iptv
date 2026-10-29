import SwiftUI

/// Netflix-style season picker followed by the selected season's episodes.
struct SeasonEpisodesView: View {
    let detail: SeriesDetail
    @Binding var season: Int
    /// Shown when an episode has no still of its own.
    let fallbackArtwork: URL?
    /// Watched fraction of an episode, nil when not started.
    var progress: (Episode) -> Double? = { _ in nil }
    /// Whether an episode was watched to the end.
    var isWatched: (Episode) -> Bool = { _ in false }
    let onPlay: (Episode) -> Void

    private var seasons: [Int] { detail.seasons.keys.sorted() }
    private var episodes: [Episode] { detail.seasons[season] ?? [] }
    private var thumbnailWidth: CGFloat { Theme.posterWidth * 1.1 }

    var body: some View {
        #if os(tvOS)
        tvBody
        #else
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                seasonPicker
                Spacer()
                Text(episodes.count == 1 ? "1 episode" : "\(episodes.count) episodes")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(episodes) { episode in
                    Button { onPlay(episode) } label: {
                        row(episode)
                    }
                    .buttonStyle(.plain)
                    if episode.id != episodes.last?.id {
                        Divider().overlay(.white.opacity(0.08))
                    }
                }
            }
        }
        #endif
    }

    #if os(tvOS)
    // MARK: Apple TV

    /// Seasons as a segmented control (moving the focus over it switches season), episodes as a shelf of
    /// 16:9 lockups.
    private var tvBody: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 30) {
                if seasons.count > 1 {
                    Picker("Season", selection: $season) {
                        ForEach(seasons, id: \.self) { value in
                            Text(seasonName(value)).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                } else {
                    Text(seasonName(season)).font(.headline)
                }
                Text(episodes.count == 1 ? "1 episode" : "\(episodes.count) episodes")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: LockupMetrics.rowSpacing) {
                    ForEach(episodes) { episode in
                        Button { onPlay(episode) } label: {
                            tvLockup(episode)
                        }
                        .lockupButtonStyle()
                    }
                }
                .padding(.vertical, 40)
            }
            .scrollClipDisabled()
        }
    }

    private static let tvStillWidth: CGFloat = 420

    private func tvLockup(_ episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            still(episode)
                .frame(width: Self.tvStillWidth, height: Self.tvStillWidth * 9 / 16)
                .overlay(alignment: .bottom) {
                    if let fraction = progress(episode) {
                        WatchProgressBar(fraction: fraction)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .lockupArtwork()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(episode.episode). \(episode.title)")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if isWatched(episode) {
                    WatchedBadge()
                }
            }
            if let plot = episode.plot, !plot.isEmpty {
                Text(plot)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
            }
        }
        .frame(width: Self.tvStillWidth, alignment: .leading)
    }
    #endif

    // MARK: Season picker

    @ViewBuilder
    private var seasonPicker: some View {
        if seasons.count > 1 {
            Menu {
                ForEach(seasons, id: \.self) { value in
                    Button {
                        season = value
                    } label: {
                        if value == season {
                            Label(seasonName(value), systemImage: "checkmark")
                        } else {
                            Text(seasonName(value))
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(seasonName(season))
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        } else {
            Text(seasonName(season)).font(.headline)
        }
    }

    private func seasonName(_ value: Int) -> String {
        value == 0 ? "Specials" : "Season \(value)"
    }

    /// The episode's still, else the series artwork.
    private func still(_ episode: Episode) -> some View {
        AsyncImage(url: episode.posterURL ?? fallbackArtwork) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Theme.surface
            }
        }
    }

    // MARK: Episode row

    private func row(_ episode: Episode) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                still(episode)
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
            }
            .frame(width: thumbnailWidth, height: thumbnailWidth * 9 / 16)
            .overlay(alignment: .bottom) {
                if let fraction = progress(episode) {
                    WatchProgressBar(fraction: fraction)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(episode.episode). \(episode.title)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    if isWatched(episode) {
                        WatchedBadge()
                    }
                }
                if let plot = episode.plot, !plot.isEmpty {
                    Text(plot)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
