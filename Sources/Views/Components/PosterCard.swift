import SwiftUI

struct PosterCard: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            poster
            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Theme.posterWidth, alignment: .leading)
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
