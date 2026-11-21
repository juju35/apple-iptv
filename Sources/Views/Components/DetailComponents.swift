import SwiftUI

#if !os(tvOS)
/// Netflix's top of the detail sheet: the artwork edge to edge, fading into the page under the title. The poster
/// already loaded for the row shows at once, a sharper copy replaces it.
struct DetailBackdrop: View {
    let item: MediaItem

    #if os(macOS)
    private static let height: CGFloat = 340
    #else
    private static let height: CGFloat = 300
    #endif

    var body: some View {
        ZStack {
            RemoteImage(url: item.posterURL, maxPixelSize: 1200) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RemoteImage(url: item.posterURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    GeneratedArtwork(title: item.name, kind: item.kind, showsTitle: false)
                }
            }
            .frame(height: Self.height)
            .frame(maxWidth: .infinity, alignment: .top)
            .clipped()
            LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.3))
            LinearGradient(stops: [.init(color: .clear, location: 0.45), .init(color: Theme.background, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .frame(height: Self.height)
    }
}

/// Title, then a line of facts: year, rating, list, and a "Live" tag for channels.
struct DetailHeader: View {
    @EnvironmentObject private var store: AppStore
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.name)
                .font(.title.weight(.heavy))
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            HStack(spacing: 10) {
                if item.kind == .live {
                    Text("Live")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 3))
                }
                if let year = item.year, !year.isEmpty {
                    Text(year)
                }
                if let rating = item.rating, rating > 0 {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .labelStyle(.titleAndIcon)
                }
                Text(store.categoryName(item.categoryId, kind: item.kind))
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// The icons under the summary: My List (Favorites for a channel).
struct DetailIconActions: View {
    @EnvironmentObject private var store: AppStore
    let item: MediaItem

    var body: some View {
        let isFavorite = store.isFavorite(item)
        let title: LocalizedStringKey
        let symbol: String
        let accessibility: LocalizedStringKey
        if item.kind == .live {
            title = "Favorites"
            symbol = isFavorite ? "heart.fill" : "heart"
            accessibility = isFavorite ? "Remove from Favorites" : "Add to Favorites"
        } else {
            title = "My List"
            symbol = isFavorite ? "checkmark" : "plus"
            accessibility = isFavorite ? "Remove from My List" : "Add to My List"
        }
        return HStack(spacing: 18) {
            IconActionButton(title: title, systemImage: symbol) {
                store.toggleFavorite(item)
            }
            .accessibilityLabel(accessibility)
        }
        .sensoryFeedback(.selection, trigger: isFavorite)
    }
}
#endif
