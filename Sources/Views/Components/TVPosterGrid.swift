#if os(tvOS)
import SwiftUI
import TVUIKit
import UIKit

/// Apple TV poster grid backed by a `UICollectionView`: cell reuse, prefetching and the system's
/// lockup focus (`TVPosterView`) keep scrolling smooth through catalogues of thousands of titles,
/// where SwiftUI grids crawled. Continue Watching and Favorites are horizontal sections of the same
/// collection view (a hosted SwiftUI header couldn't size itself); only the chips are SwiftUI.
struct TVPosterGrid<Chips: View>: UIViewControllerRepresentable {
    @EnvironmentObject private var store: AppStore
    let items: [MediaItem]
    let continueWatching: [ContinueWatchingEntry]
    let favorites: [MediaItem]
    let onSelect: (MediaItem) -> Void
    @ViewBuilder let chips: () -> Chips

    func makeUIViewController(context: Context) -> TVPosterGridController {
        TVPosterGridController()
    }

    func updateUIViewController(_ controller: TVPosterGridController, context: Context) {
        controller.onSelect = onSelect
        controller.onToggleFavorite = { [store] in store.toggleFavorite($0) }
        controller.onRemoveFromContinueWatching = { [store] in store.removeFromContinueWatching($0) }
        // A hosting configuration doesn't inherit the environment: hand the store over.
        controller.update(.init(items: items, continueWatching: continueWatching, favorites: favorites,
                                favoriteIDs: Set(store.favoriteIDs)),
                          chips: AnyView(chips().environmentObject(store)))
    }
}

final class TVPosterGridController: UIViewController, UICollectionViewDelegate,
    UICollectionViewDataSourcePrefetching {
    struct Content {
        var items: [MediaItem] = []
        var continueWatching: [ContinueWatchingEntry] = []
        var favorites: [MediaItem] = []
        var favoriteIDs: Set<String> = []
    }

    enum Section: Int, Hashable { case chips, continueWatching, favorites, posters }
    private struct Row: Hashable {
        let section: Section
        let id: String
    }

    var onSelect: (MediaItem) -> Void = { _ in }
    var onToggleFavorite: (MediaItem) -> Void = { _ in }
    var onRemoveFromContinueWatching: (MediaItem) -> Void = { _ in }

    private var content = Content()
    private var itemsByID: [String: MediaItem] = [:]
    private var progressByID: [String: PlaybackProgress] = [:]
    private var chips = AnyView(EmptyView())
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>!

    private static let posterSize = CGSize(width: Theme.posterWidth, height: Theme.posterWidth / Theme.posterAspect)
    private static let titleKind = "title"
    private static let chipsRow = Row(section: .chips, id: "chips")

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.remembersLastFocusedIndexPath = true
        view.addSubview(collectionView)

        let chipsRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Row> { [weak self] cell, _, _ in
            guard let self else { return }
            cell.contentConfiguration = UIHostingConfiguration { self.chips }.margins(.all, 0)
        }
        let posterRegistration = UICollectionView.CellRegistration<PosterCell, Row> { [weak self] cell, _, row in
            guard let self, let item = itemsByID[row.id] else { return }
            let progress = row.section == .continueWatching ? progressByID[row.id] : nil
            cell.configure(item, size: Self.posterSize, isFavorite: content.favoriteIDs.contains(row.id),
                           progress: progress?.fraction, subtitle: progress?.episodeLabel)
        }
        let titleRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(
            elementKind: Self.titleKind
        ) { [weak self] view, _, indexPath in
            let section = self?.dataSource.sectionIdentifier(for: indexPath.section)
            let title = section == .continueWatching
                ? String(localized: "Continue Watching") : String(localized: "Favorites")
            view.contentConfiguration = UIHostingConfiguration {
                Text(title).font(.title3.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
            }
            .margins(.all, 0)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { view, indexPath, row in
            row.section == .chips
                ? view.dequeueConfiguredReusableCell(using: chipsRegistration, for: indexPath, item: row)
                : view.dequeueConfiguredReusableCell(using: posterRegistration, for: indexPath, item: row)
        }
        dataSource.supplementaryViewProvider = { view, _, indexPath in
            view.dequeueConfiguredReusableSupplementary(using: titleRegistration, for: indexPath)
        }
    }

    func update(_ new: Content, chips: AnyView) {
        loadViewIfNeeded()
        self.chips = chips
        let old = content
        content = new
        for item in new.items + new.favorites + new.continueWatching.map(\.item) {
            itemsByID[item.id] = item
        }
        progressByID = Dictionary(new.continueWatching.map { ($0.item.id, $0.progress) },
                                  uniquingKeysWith: { first, _ in first })

        var snapshot = dataSource.snapshot()
        let structureChanged = snapshot.numberOfSections == 0
            || new.items.map(\.id) != old.items.map(\.id)
            || new.continueWatching.map(\.id) != old.continueWatching.map(\.id)
            || new.favorites.map(\.id) != old.favorites.map(\.id)
        if structureChanged {
            snapshot = NSDiffableDataSourceSnapshot()
            snapshot.appendSections([.chips])
            snapshot.appendItems([Self.chipsRow])
            append(new.continueWatching.map(\.item.id), to: .continueWatching, in: &snapshot)
            append(new.favorites.map(\.id), to: .favorites, in: &snapshot)
            append(new.items.map(\.id), to: .posters, in: &snapshot)
        } else {
            if new.favoriteIDs != old.favoriteIDs {
                snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { $0.section != .chips })
            }
            // The chips follow their selection.
            snapshot.reconfigureItems([Self.chipsRow])
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func append(_ ids: [String], to section: Section,
                        in snapshot: inout NSDiffableDataSourceSnapshot<Section, Row>) {
        guard !ids.isEmpty else { return }
        snapshot.appendSections([section])
        // Duplicate ids would crash the diffable data source.
        var seen = Set<String>()
        snapshot.appendItems(ids.filter { seen.insert($0).inserted }.map { Row(section: section, id: $0) })
    }

    // MARK: Layout

    private func layout() -> UICollectionViewCompositionalLayout {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.interSectionSpacing = 50
        return UICollectionViewCompositionalLayout(sectionProvider: { [weak self] index, environment in
            switch self?.dataSource.sectionIdentifier(for: index) {
            case .chips: Self.chipsSection()
            case .continueWatching, .favorites: Self.rowSection()
            default: Self.gridSection(width: environment.container.effectiveContentSize.width)
            }
        }, configuration: configuration)
    }

    private static let inset: CGFloat = 40
    private static var cellSize: NSCollectionLayoutSize {
        .init(widthDimension: .absolute(posterSize.width), heightDimension: .absolute(posterSize.height + 90))
    }

    private static func chipsSection() -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(110))
        let section = NSCollectionLayoutSection(group: .horizontal(layoutSize: size, subitems: [.init(layoutSize: size)]))
        section.contentInsets.top = 20
        return section
    }

    /// Continue Watching and Favorites: one horizontal row under a title.
    private static func rowSection() -> NSCollectionLayoutSection {
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: cellSize, subitems: [.init(layoutSize: cellSize)])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = LockupMetrics.rowSpacing
        section.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: inset, bottom: 0, trailing: inset)
        let title = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(50)),
            elementKind: titleKind, alignment: .top)
        title.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)
        section.boundarySupplementaryItems = [title]
        return section
    }

    private static func gridSection(width: CGFloat) -> NSCollectionLayoutSection {
        let spacing = LockupMetrics.gridSpacing
        let columns = max(1, Int((width - 2 * inset + spacing) / (posterSize.width + spacing)))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: cellSize.heightDimension),
            repeatingSubitem: NSCollectionLayoutItem(layoutSize: cellSize), count: columns)
        group.interItemSpacing = .fixed(spacing)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = LockupMetrics.gridRowSpacing
        section.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: inset, bottom: 60, trailing: inset)
        return section
    }

    private func item(at indexPath: IndexPath) -> (item: MediaItem, section: Section)? {
        guard let row = dataSource.itemIdentifier(for: indexPath), row.section != .chips,
              let item = itemsByID[row.id] else { return nil }
        return (item, row.section)
    }

    // MARK: UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
        // The chips' own SwiftUI buttons take the focus, not their cell.
        dataSource.itemIdentifier(for: indexPath)?.section != .chips
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let found = item(at: indexPath) { onSelect(found.item) }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first, let found = item(at: indexPath) else { return nil }
        let item = found.item
        let isFavorite = content.favoriteIDs.contains(item.id)
        let favoriteTitle = isFavorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites")
        let inContinueWatching = found.section == .continueWatching
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            var actions = [
                UIAction(title: favoriteTitle, image: UIImage(systemName: isFavorite ? "heart.slash" : "heart")) { _ in
                    self?.onToggleFavorite(item)
                },
            ]
            if inContinueWatching {
                actions.append(UIAction(title: String(localized: "Remove from Continue Watching"),
                                        image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { _ in
                    self?.onRemoveFromContinueWatching(item)
                })
            }
            return UIMenu(children: actions)
        })
    }

    // MARK: Prefetching

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        ImageLoader.shared.prefetch(indexPaths.compactMap { item(at: $0)?.item.posterURL })
    }
}

/// A poster lockup: the system's focus lift, tilt and title motion.
private final class PosterCell: UICollectionViewCell {
    private let poster = TVPosterView()
    private let heart = UIImageView(image: UIImage(systemName: "heart.fill"))
    private let progressView = UIProgressView(progressViewStyle: .bar)
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
        progressView.progressTintColor = UIColor(Theme.accent)
        progressView.trackTintColor = UIColor(white: 1, alpha: 0.25)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        let overlay = poster.imageView.overlayContentView
        overlay.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func prepareForReuse() {
        super.prepareForReuse()
        loading?.cancel()
        poster.image = nil
    }

    func configure(_ item: MediaItem, size: CGSize, isFavorite: Bool, progress: Double?, subtitle: String?) {
        poster.contentSize = size
        poster.title = item.name
        poster.subtitle = subtitle
        heart.isHidden = !isFavorite
        progressView.isHidden = progress == nil
        progressView.progress = Float(progress ?? 0)
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
