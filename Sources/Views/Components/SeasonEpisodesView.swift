import SwiftUI

/// Netflix-style season picker followed by the selected season's episodes.
struct SeasonEpisodesView: View {
    let detail: SeriesDetail
    @Binding var season: Int
    /// Shown when an episode has no still of its own.
    let fallbackArtwork: URL?
    let onPlay: (Episode) -> Void

    private var seasons: [Int] { detail.seasons.keys.sorted() }
    private var episodes: [Episode] { detail.seasons[season] ?? [] }
    private var thumbnailWidth: CGFloat { Theme.posterWidth * 1.1 }

    var body: some View {
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
    }

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

    // MARK: Episode row

    private func row(_ episode: Episode) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                AsyncImage(url: episode.posterURL ?? fallbackArtwork) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Theme.surface
                    }
                }
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
            }
            .frame(width: thumbnailWidth, height: thumbnailWidth * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text("\(episode.episode). \(episode.title)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
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
