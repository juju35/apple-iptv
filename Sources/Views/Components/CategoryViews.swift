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
                                Image(systemName: systemImage).frame(width: Self.iconWidth)
                            }
                            Text(option.title).lineLimit(1)
                            Spacer(minLength: 4)
                            if let count = option.count {
                                Text("\(count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .font(Self.rowFont.weight(option.id == selection ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(option.id == selection ? Self.selectionFill : .clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .rowButtonStyle()
                }
            }
            .padding(8)
        }
        .background(Theme.surface.opacity(0.35))
    }

    // Apple TV: focus already highlights the row, the selection is a quiet fill.
    // (Computed: generic types can't have static stored properties.)
    #if os(tvOS)
    private static var iconWidth: CGFloat { 40 }
    private static var rowFont: Font { .callout }
    private static var selectionFill: Color { .white.opacity(0.14) }
    #else
    private static var iconWidth: CGFloat { 18 }
    private static var rowFont: Font { .subheadline }
    private static var selectionFill: Color { Theme.accent.opacity(0.9) }
    #endif
}

/// Horizontal, scrolling category chips.
struct CategoryChips<ID: Hashable>: View {
    let options: [ChipOption<ID>]
    @Binding var selection: ID

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(options) { option in
                    chip(option)
                }
            }
            .padding(.horizontal)
            #if os(tvOS)
            .padding(.vertical, 20)
            #endif
        }
        #if os(tvOS)
        .scrollClipDisabled()
        #endif
    }

    @ViewBuilder
    private func chip(_ option: ChipOption<ID>) -> some View {
        let isSelected = option.id == selection
        #if os(tvOS)
        // System capsules: translucent, white when focused; the selected one stays filled.
        Button {
            selection = option.id
        } label: {
            label(option)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .overlay {
            if isSelected {
                Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 3)
            }
        }
        #else
        Button {
            selection = option.id
        } label: {
            label(option)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(isSelected ? Theme.accent : Theme.surface))
                .foregroundStyle(isSelected ? .white : Theme.textSecondary)
        }
        .buttonStyle(.plain)
        #endif
    }

    private func label(_ option: ChipOption<ID>) -> some View {
        HStack(spacing: 6) {
            if let systemImage = option.systemImage {
                Image(systemName: systemImage)
            }
            Text(option.title).lineLimit(1)
        }
        #if os(tvOS)
        .font(.callout.weight(.semibold))
        #else
        .font(.subheadline.weight(.semibold))
        #endif
    }
}

// MARK: - Favorites context menu

/// Long press (or right click) on a channel, movie or series to add or remove it from the favorites.
private struct FavoriteContextMenu: ViewModifier {
    @EnvironmentObject private var store: AppStore
    let item: MediaItem
    /// Offers to drop the item from Continue Watching (in that row).
    let inContinueWatching: Bool

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
            if inContinueWatching {
                Button(role: .destructive) {
                    store.removeFromContinueWatching(item)
                } label: {
                    Label("Remove from Continue Watching", systemImage: "xmark.circle")
                }
            }
        }
    }
}

extension View {
    /// Long press (right click on the Mac): add to / remove from the favorites, and in the Continue Watching row,
    /// drop the movie or series from it.
    func favoriteContextMenu(_ item: MediaItem, inContinueWatching: Bool = false) -> some View {
        modifier(FavoriteContextMenu(item: item, inContinueWatching: inContinueWatching))
    }
}
