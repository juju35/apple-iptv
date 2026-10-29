#if os(tvOS)
import SwiftUI
import TVUIKit
import UIKit

/// Apple TV poster grid backed by a `UICollectionView`: cell reuse, prefetching and the system's
/// lockup focus (`TVPosterView`) keep scrolling smooth through catalogues of thousands of titles,
/// where SwiftUI grids crawled. `header` (chips, Continue Watching…) scrolls with the posters.
struct TVPosterGrid<Header: View>: UIViewControllerRepresentable {
    @EnvironmentObject private var store: AppStore
    let items: [MediaItem]
    let favoriteIDs: Set<String>
    let onSelect: (MediaItem) -> Void
    let onToggleFavorite: (MediaItem) -> Void
    @ViewBuilder let header: () -> Header

    func makeUIViewController(context: Context) -> TVPosterGridController {
        TVPosterGridController()
    }

    func updateUIViewController(_ controller: TVPosterGridController, context: Context) {
        controller.onSelect = onSelect
        controller.onToggleFavorite = onToggleFavorite
        // A hosting configuration doesn't inherit the environment: hand the store over.
        controller.update(items: items, favoriteIDs: favoriteIDs, header: AnyView(header().environmentObject(store)))
    }
}

final class TVPosterGridController: UIViewController, UICollectionViewDelegate,
    UICollectionViewDataSourcePrefetching {
    private enum Section { case header, posters }
    private enum Row: Hashable {
        case header
        case poster(String)
    }

    var onSelect: (MediaItem) -> Void = { _ in }
    var onToggleFavorite: (MediaItem) -> Void = { _ in }

    private var itemsByID: [String: MediaItem] = [:]
    private var itemIDs: [String] = []
    private var favoriteIDs: Set<String> = []
    private var header = AnyView(EmptyView())
    /// Measured: a self-sizing hosted cell kept its estimate and the posters overlapped the header's rows.
    private var headerHeight: CGFloat = 400
    private let sizer = UIHostingController(rootView: AnyView(EmptyView()))
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>!

    private static let posterSize = CGSize(width: Theme.posterWidth, height: Theme.posterWidth / Theme.posterAspect)

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.remembersLastFocusedIndexPath = true
        view.addSubview(collectionView)

        let headerRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Row> { [weak self] cell, _, _ in
            guard let self else { return }
            cell.contentConfiguration = UIHostingConfiguration { self.header }.margins(.all, 0)
        }
        let posterRegistration = UICollectionView.CellRegistration<PosterCell, Row> { [weak self] cell, _, row in
            guard let self, case .poster(let id) = row, let item = itemsByID[id] else { return }
            cell.configure(item, size: Self.posterSize, isFavorite: favoriteIDs.contains(id))
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { view, indexPath, row in
            switch row {
            case .header: view.dequeueConfiguredReusableCell(using: headerRegistration, for: indexPath, item: row)
            case .poster: view.dequeueConfiguredReusableCell(using: posterRegistration, for: indexPath, item: row)
            }
        }
    }

    func update(items: [MediaItem], favoriteIDs: Set<String>, header: AnyView) {
        loadViewIfNeeded()
        self.header = header
        sizer.rootView = header
        let width = view.bounds.width > 0 ? view.bounds.width : 1920
        let height = ceil(sizer.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        if abs(height - headerHeight) > 0.5 {
            headerHeight = height
            collectionView.collectionViewLayout.invalidateLayout()
        }
        let ids = items.map(\.id)
        let favoritesChanged = favoriteIDs != self.favoriteIDs
        self.favoriteIDs = favoriteIDs
        var snapshot = dataSource.snapshot()
        if ids != itemIDs || snapshot.numberOfSections == 0 {
            itemIDs = ids
            itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            snapshot = NSDiffableDataSourceSnapshot()
            snapshot.appendSections([.header, .posters])
            snapshot.appendItems([.header], toSection: .header)
            // Duplicate ids would crash the diffable data source.
            var seen = Set<String>()
            snapshot.appendItems(ids.filter { seen.insert($0).inserted }.map(Row.poster), toSection: .posters)
        } else if favoritesChanged {
            snapshot.reconfigureItems(snapshot.itemIdentifiers(inSection: .posters))
        }
        // The header's chips and rows follow the store.
        snapshot.reconfigureItems([.header])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func layout() -> UICollectionViewCompositionalLayout {
        let posterSize = Self.posterSize
        return UICollectionViewCompositionalLayout { [weak self] section, environment in
            if section == 0 {
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                                  heightDimension: .absolute(self?.headerHeight ?? 400))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [.init(layoutSize: size)])
                return NSCollectionLayoutSection(group: group)
            }
            let spacing = LockupMetrics.gridSpacing
            let width = environment.container.effectiveContentSize.width - 2 * 40
            let columns = max(1, Int((width + spacing) / (posterSize.width + spacing)))
            let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(posterSize.width),
                                                  heightDimension: .absolute(posterSize.height + 60))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                                   heightDimension: .absolute(posterSize.height + 60)),
                repeatingSubitem: NSCollectionLayoutItem(layoutSize: itemSize), count: columns)
            group.interItemSpacing = .fixed(spacing)
            let posters = NSCollectionLayoutSection(group: group)
            posters.interGroupSpacing = LockupMetrics.gridRowSpacing
            posters.contentInsets = NSDirectionalEdgeInsets(top: 30, leading: 40, bottom: 60, trailing: 40)
            return posters
        }
    }

    private func item(at indexPath: IndexPath) -> MediaItem? {
        guard case .poster(let id) = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return itemsByID[id]
    }

    // MARK: UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
        // The header's own SwiftUI buttons take the focus, not its cell.
        dataSource.itemIdentifier(for: indexPath) != .header
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let item = item(at: indexPath) { onSelect(item) }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first, let item = item(at: indexPath) else { return nil }
        let isFavorite = favoriteIDs.contains(item.id)
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(title: isFavorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"),
                         image: UIImage(systemName: isFavorite ? "heart.slash" : "heart")) { _ in
                    self?.onToggleFavorite(item)
                },
            ])
        })
    }

    // MARK: Prefetching

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        ImageLoader.shared.prefetch(indexPaths.compactMap { item(at: $0)?.posterURL })
    }
}

/// A poster lockup: the system's focus lift, tilt and title motion.
private final class PosterCell: UICollectionViewCell {
    private let poster = TVPosterView()
    private let heart = UIImageView(image: UIImage(systemName: "heart.fill"))
    private var loading: Task<Void, Never>?
    private var url: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        poster.translatesAutoresizingMaskIntoConstraints = false
        poster.imageView.contentMode = .scaleAspectFill
        poster.imageView.backgroundColor = UIColor(white: 0.16, alpha: 1)
        contentView.addSubview(poster)
        NSLayoutConstraint.activate([
            poster.topAnchor.constraint(equalTo: contentView.topAnchor),
            poster.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            poster.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        heart.tintColor = UIColor(Theme.accent)
        heart.translatesAutoresizingMaskIntoConstraints = false
        poster.imageView.overlayContentView.addSubview(heart)
        NSLayoutConstraint.activate([
            heart.topAnchor.constraint(equalTo: poster.imageView.overlayContentView.topAnchor, constant: 10),
            heart.trailingAnchor.constraint(equalTo: poster.imageView.overlayContentView.trailingAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func prepareForReuse() {
        super.prepareForReuse()
        loading?.cancel()
        poster.image = nil
    }

    func configure(_ item: MediaItem, size: CGSize, isFavorite: Bool) {
        poster.contentSize = size
        poster.title = item.name
        heart.isHidden = !isFavorite
        url = item.posterURL
        guard let url = item.posterURL else { return }
        if let cached = ImageLoader.shared.cached(url, maxPixelSize: 600) {
            poster.image = UIImage(cgImage: cached)
            return
        }
        loading?.cancel()
        loading = Task { [weak self] in
            let image = await ImageLoader.shared.image(for: url, maxPixelSize: 600)
            guard let self, !Task.isCancelled, self.url == url, let image else { return }
            self.poster.image = UIImage(cgImage: image)
        }
    }
}
#endif
