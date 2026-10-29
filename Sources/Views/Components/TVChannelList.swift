#if os(tvOS)
import SwiftUI
import UIKit

/// Apple TV channel list backed by a `UICollectionView`: reused cells and prefetched logos keep
/// scrolling smooth through hundreds of channels. Rows are the SwiftUI `ChannelRow` in hosted cells.
struct TVChannelList: UIViewControllerRepresentable {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var guide: EPGStore
    let channels: [MediaItem]
    let highlightedID: String?
    let onSelect: (MediaItem) -> Void
    /// The channel the focus rests on, once it stops moving.
    let onFocusRest: (MediaItem) -> Void

    func makeUIViewController(context: Context) -> TVChannelListController {
        TVChannelListController()
    }

    func updateUIViewController(_ controller: TVChannelListController, context: Context) {
        controller.onSelect = onSelect
        controller.onFocusRest = onFocusRest
        controller.onToggleFavorite = { [store] in store.toggleFavorite($0) }
        // Hosted cells don't inherit the environment: hand the stores over.
        controller.wrap = { [store, guide] row in AnyView(row.environmentObject(store).environmentObject(guide)) }
        controller.update(channels: channels, highlightedID: highlightedID,
                          favorites: Set(store.favoriteIDs), guideDate: guide.updatedAt)
    }
}

final class TVChannelListController: UIViewController, UICollectionViewDelegate,
    UICollectionViewDataSourcePrefetching {
    var onSelect: (MediaItem) -> Void = { _ in }
    var onFocusRest: (MediaItem) -> Void = { _ in }
    var onToggleFavorite: (MediaItem) -> Void = { _ in }
    var wrap: (AnyView) -> AnyView = { $0 }

    private var channelsByID: [String: MediaItem] = [:]
    private var channelIDs: [String] = []
    private var highlightedID: String?
    private var favorites: Set<String> = []
    private var guideDate: Date?
    private var focusRest: Task<Void, Never>?
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!

    override func viewDidLoad() {
        super.viewDidLoad()
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(110))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 10
        section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 40, trailing: 16)
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: UICollectionViewCompositionalLayout(section: section))
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.remembersLastFocusedIndexPath = true
        view.addSubview(collectionView)

        let registration = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, _, id in
            guard let self, let channel = channelsByID[id] else { return }
            let isHighlighted = id == highlightedID
            let wrap = wrap
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    wrap(AnyView(ChannelRow(channel: channel, isHighlighted: isHighlighted)))
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                                .fill(Color.white.opacity(state.isFocused ? 0.22 : 0.06))
                        )
                        .scaleEffect(state.isFocused ? 1.04 : 1)
                        .shadow(color: .black.opacity(state.isFocused ? 0.5 : 0), radius: 14, y: 8)
                        .animation(.easeOut(duration: 0.15), value: state.isFocused)
                }
                .margins(.all, 0)
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { view, indexPath, id in
            view.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
        }
    }

    func update(channels: [MediaItem], highlightedID: String?, favorites: Set<String>, guideDate: Date?) {
        loadViewIfNeeded()
        let ids = channels.map(\.id)
        var snapshot = dataSource.snapshot()
        if ids != channelIDs || snapshot.numberOfSections == 0 {
            channelIDs = ids
            channelsByID = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            snapshot = NSDiffableDataSourceSnapshot()
            snapshot.appendSections([0])
            // Duplicate ids would crash the diffable data source.
            var seen = Set<String>()
            snapshot.appendItems(ids.filter { seen.insert($0).inserted })
        } else {
            var changed = Set<String>()
            if highlightedID != self.highlightedID {
                changed.formUnion([highlightedID, self.highlightedID].compactMap { $0 })
            }
            changed.formUnion(favorites.symmetricDifference(self.favorites))
            let reload = guideDate != self.guideDate
                ? snapshot.itemIdentifiers : snapshot.itemIdentifiers.filter(changed.contains)
            snapshot.reconfigureItems(reload)
        }
        self.highlightedID = highlightedID
        self.favorites = favorites
        self.guideDate = guideDate
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func channel(at indexPath: IndexPath) -> MediaItem? {
        dataSource.itemIdentifier(for: indexPath).flatMap { channelsByID[$0] }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let channel = channel(at: indexPath) { onSelect(channel) }
    }

    func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                        with coordinator: UIFocusAnimationCoordinator) {
        focusRest?.cancel()
        guard let indexPath = context.nextFocusedIndexPath, let channel = channel(at: indexPath) else { return }
        // Once the focus rests: the programme panel isn't updated on every step of a fast scroll.
        focusRest = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.onFocusRest(channel)
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first, let channel = channel(at: indexPath) else { return nil }
        let isFavorite = favorites.contains(channel.id)
        let title = isFavorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites")
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(title: title, image: UIImage(systemName: isFavorite ? "heart.slash" : "heart")) { _ in
                    self?.onToggleFavorite(channel)
                },
            ])
        })
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        ImageLoader.shared.prefetch(indexPaths.compactMap { channel(at: $0)?.posterURL }, maxPixelSize: 300)
    }
}
#endif
