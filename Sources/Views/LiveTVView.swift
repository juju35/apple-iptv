import SwiftUI

/// Live TV: categories, channels and what's on side by side on large screens
/// (Mac, iPad, Apple TV); category chips above the channel list on iPhone.
struct LiveTVView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.presentPlayer) private var presentPlayer
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// Sidebar / chip selection.
    enum ChannelGroup: Hashable {
        case all, favorites, recent
        case category(String)
    }

    @State private var group: ChannelGroup = .all
    @State private var search = ""
    /// Channel shown in the info panel (large screens).
    @State private var highlighted: MediaItem?
    /// Channel whose detail sheet is open (iPhone).
    @State private var detailItem: MediaItem?
    @State private var playback: PlaybackRequest?
    @State private var resolvingID: String?
    @State private var playError: String?

    private var isWide: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        true
        #endif
    }

    private var channels: [MediaItem] {
        var items: [MediaItem]
        switch group {
        case .all: items = store.liveItems
        case .favorites: items = store.favorites(.live)
        case .recent: items = store.recentChannels()
        case .category(let id): items = store.liveItems.filter { $0.belongs(to: id) }
        }
        if !search.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(search) }
        }
        return items
    }

    /// Categories that still have channels once filters apply, with their channel counts.
    private var groups: [ChipOption<ChannelGroup>] {
        let counts = Dictionary(store.liveItems.flatMap(\.categoryIds).map { ($0, 1) }, uniquingKeysWith: +)
        var options = [ChipOption(id: ChannelGroup.all, title: "All Channels", systemImage: "tv",
                                  count: store.liveItems.count)]
        let favorites = store.favorites(.live).count
        if favorites > 0 {
            options.append(ChipOption(id: .favorites, title: "Favorites", systemImage: "heart.fill", count: favorites))
        }
        let recent = store.recentChannels().count
        if recent > 0 {
            options.append(ChipOption(id: .recent, title: "Recently Watched", systemImage: "clock.arrow.circlepath",
                                      count: recent))
        }
        options += store.liveCategories.compactMap { category in
            guard let count = counts[category.id] else { return nil }
            return ChipOption(id: .category(category.id), title: category.name, count: count)
        }
        return options
    }

    var body: some View {
        NavigationStack {
            Group {
                if isWide {
                    wideLayout
                } else {
                    compactLayout
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Live TV")
            .providerToolbar()
            .modifier(BrowseSearch(text: $search))
            .sheet(item: $detailItem) { item in
                MediaDetailView(item: item)
            }
            .fullScreenCoverCompat(item: $playback) { request in
                PlayerView(request: request)
            }
        }
    }

    // MARK: Layouts

    private var wideLayout: some View {
        HStack(spacing: 0) {
            CategorySidebar(options: groups, selection: $group)
                .frame(width: Theme.sidebarWidth)
            Divider().overlay(.white.opacity(0.08))
            channelList
                .frame(minWidth: Theme.channelListMinWidth, maxWidth: Theme.channelListMaxWidth)
            Divider().overlay(.white.opacity(0.08))
            if let channel = highlighted ?? channels.first {
                ChannelInfoPanel(channel: channel, isResolving: resolvingID == channel.id, error: playError) {
                    watch(channel)
                }
                .id(channel.id)
            } else {
                ContentUnavailableView("No channels", systemImage: "tv.slash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            CategoryChips(options: groups, selection: $group)
                .padding(.vertical, 8)
            channelList
        }
    }

    private var channelList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(channels) { channel in
                    Button {
                        select(channel)
                    } label: {
                        ChannelRow(channel: channel, isHighlighted: isWide && channel.id == highlightedID)
                    }
                    .buttonStyle(.plain)
                    .favoriteContextMenu(channel)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .onChange(of: group) { _, _ in highlighted = nil }
    }

    private var highlightedID: String? { (highlighted ?? channels.first)?.id }

    // MARK: Actions

    /// Large screens: the first click shows the channel's programme, the second one plays it.
    /// iPhone: opens the channel's detail sheet.
    private func select(_ channel: MediaItem) {
        guard isWide else {
            detailItem = channel
            return
        }
        if channel.id == highlightedID {
            watch(channel)
        } else {
            highlighted = channel
            playError = nil
        }
    }

    private func watch(_ channel: MediaItem) {
        guard resolvingID == nil else { return }
        resolvingID = channel.id
        playError = nil
        Task { @MainActor in
            defer { resolvingID = nil }
            do {
                var request = try await store.playbackRequest(for: channel)
                request.channelList = channels
                if let presentPlayer { presentPlayer(request) } else { playback = request }
            } catch {
                playError = error.localizedDescription
            }
        }
    }
}

// MARK: - Channel row

/// Logo, name, category and quality of a channel.
struct ChannelRow: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var guide: EPGStore
    let channel: MediaItem
    var isHighlighted = false

    var body: some View {
        HStack(spacing: 12) {
            ChannelLogo(channel: channel)
                .frame(width: Theme.channelLogoWidth, height: Theme.channelLogoWidth * 0.6)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                // What's on from the guide, else the channel's list.
                if let now = guide.current(for: channel) {
                    Text(now.title)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    WatchProgressBar(fraction: Date().timeIntervalSince(now.start) / now.end.timeIntervalSince(now.start))
                        .frame(maxWidth: 120)
                        .clipShape(Capsule())
                } else {
                    Text(store.categoryName(channel.categoryId, kind: .live))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let quality = ContentTags.quality(of: channel.name) {
                QualityBadge(text: quality)
            }
            if store.isFavorite(channel) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(isHighlighted ? Theme.accent.opacity(0.22) : Theme.surface.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .strokeBorder(isHighlighted ? Theme.accent.opacity(0.7) : .clear)
        )
        .contentShape(Rectangle())
    }
}

/// Channel logo on a dark tile, letterboxed; generated artwork when the channel has none.
struct ChannelLogo: View {
    let channel: MediaItem

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06))
            AsyncImage(url: channel.posterURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFit().padding(6)
                } else {
                    GeneratedArtwork(title: channel.name, kind: .live)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// "FHD", "4K"… as a small outlined capsule.
struct QualityBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(.white.opacity(0.5)))
            .foregroundStyle(.white.opacity(0.85))
    }
}

// MARK: - Info panel

/// What's on the highlighted channel: logo, now / next from the EPG, Watch and Favorite.
struct ChannelInfoPanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var guide: EPGStore
    let channel: MediaItem
    let isResolving: Bool
    let error: String?
    let onWatch: () -> Void

    @State private var epg: [EPGEntry] = []
    @State private var isLoadingEPG = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ChannelLogo(channel: channel)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: 520)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(channel.name).font(.title2.weight(.bold))
                    if let quality = ContentTags.quality(of: channel.name) {
                        QualityBadge(text: quality)
                    }
                }

                HStack(spacing: 12) {
                    Button(action: onWatch) {
                        HStack {
                            if isResolving {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(isResolving ? "Loading…" : "Watch")
                        }
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(isResolving)

                    Button {
                        store.toggleFavorite(channel)
                    } label: {
                        Image(systemName: store.isFavorite(channel) ? "heart.fill" : "heart")
                            .foregroundStyle(store.isFavorite(channel) ? Theme.accent : .white)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(store.isFavorite(channel) ? "Remove from Favorites" : "Add to Favorites")
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }

                programme
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: "\(channel.id)-\(guide.updatedAt?.timeIntervalSince1970 ?? 0)") { await loadEPG() }
    }

    @ViewBuilder
    private var programme: some View {
        let now = Date()
        let current = epg.first { $0.start <= now && now < $0.end }
        let upcoming = epg.filter { $0.start > now }.prefix(5)
        if let current {
            VStack(alignment: .leading, spacing: 8) {
                Text("NOW").font(.caption.weight(.heavy)).foregroundStyle(Theme.accent)
                Text(current.title).font(.title3.weight(.semibold))
                HStack {
                    Text(current.start, style: .time)
                    WatchProgressBar(fraction: now.timeIntervalSince(current.start)
                                     / current.end.timeIntervalSince(current.start))
                        .clipShape(Capsule())
                    Text(current.end, style: .time)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                if let description = current.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(4)
                }
            }
        }
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("NEXT").font(.caption.weight(.heavy)).foregroundStyle(Theme.textSecondary)
                ForEach(upcoming) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(entry.start, style: .time)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 54, alignment: .leading)
                        Text(entry.title).font(.subheadline).lineLimit(1)
                    }
                }
            }
        }
        if current == nil && upcoming.isEmpty {
            Text(isLoadingEPG ? "Loading the programme…" : "No programme information for this channel.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func loadEPG() async {
        isLoadingEPG = true
        defer { isLoadingEPG = false }
        // The whole guide when the provider has one, else the channel's short guide.
        let cached = guide.entries(for: channel)
        if !cached.isEmpty {
            epg = cached
            return
        }
        guard let provider = store.selectedProvider else { return }
        epg = (try? await store.client(for: provider).shortEPG(forChannelRef: channel.playbackRef)) ?? []
    }
}
