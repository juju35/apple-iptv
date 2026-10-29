import SwiftUI

// MARK: - Categories

/// An entry of the category sidebar / chips.
struct ChipOption<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    var systemImage: String?
    var count: Int?
}

/// Vertical category list with counts (large screens).
struct CategorySidebar<ID: Hashable>: View {
    let options: [ChipOption<ID>]
    @Binding var selection: ID

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(options) { option in
                    Button {
                        selection = option.id
                    } label: {
                        HStack(spacing: 10) {
                            if let systemImage = option.systemImage {
                                Image(systemName: systemImage).frame(width: 18)
                            }
                            Text(option.title).lineLimit(1)
                            Spacer(minLength: 4)
                            if let count = option.count {
                                Text("\(count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .font(.subheadline.weight(option.id == selection ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(option.id == selection ? Theme.accent.opacity(0.9) : .clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .background(Theme.surface.opacity(0.35))
    }
}

/// Horizontal, scrolling category chips.
struct CategoryChips<ID: Hashable>: View {
    let options: [ChipOption<ID>]
    @Binding var selection: ID

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(options) { option in
                    Button {
                        selection = option.id
                    } label: {
                        HStack(spacing: 6) {
                            if let systemImage = option.systemImage {
                                Image(systemName: systemImage)
                            }
                            Text(option.title).lineLimit(1)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(option.id == selection ? Theme.accent : Theme.surface))
                        .foregroundStyle(option.id == selection ? .white : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Favorites context menu

/// Long press (or right click) on a channel, movie or series to add or remove it from the favorites.
private struct FavoriteContextMenu: ViewModifier {
    @EnvironmentObject private var store: AppStore
    let item: MediaItem

    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                store.toggleFavorite(item)
            } label: {
                if store.isFavorite(item) {
                    Label("Remove from Favorites", systemImage: "heart.slash")
                } else {
                    Label("Add to Favorites", systemImage: "heart")
                }
            }
        }
    }
}

extension View {
    func favoriteContextMenu(_ item: MediaItem) -> some View {
        modifier(FavoriteContextMenu(item: item))
    }
}
