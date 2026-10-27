import SwiftUI

/// Detail sheet: artwork, metadata, play button, episodes for series, EPG for live.
struct MediaDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem

    @State private var detail: SeriesDetail?
    @State private var epg: [EPGEntry] = []
    @State private var playback: PlaybackRequest?
    @State private var loadError: String?
    @State private var isResolving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if item.kind != .series {
                        playButton(label: item.kind == .live ? "Watch Live" : "Play") {
                            play(ref: item.playbackRef, ext: item.containerExtension)
                        }
                    }

                    if let plot = item.plot, !plot.isEmpty {
                        Text(plot).foregroundStyle(Theme.textSecondary)
                    }

                    if let loadError {
                        Label(loadError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }

                    if item.kind == .live, !epg.isEmpty {
                        epgSection
                    }

                    if item.kind == .series {
                        episodesSection
                    }
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
            }
            .task { await loadDetails() }
            .fullScreenCoverCompat(item: $playback) { request in
                PlayerView(request: request)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: item.posterURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Theme.surface
                }
            }
            .frame(width: Theme.posterWidth, height: Theme.posterWidth / Theme.posterAspect)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))

            VStack(alignment: .leading, spacing: 8) {
                Text(item.name).font(.title2.weight(.bold))
                if let year = item.year, !year.isEmpty {
                    Text(year).foregroundStyle(Theme.textSecondary)
                }
                if let rating = item.rating, rating > 0 {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.subheadline)
                }
                Text(store.categoryName(item.categoryId, kind: item.kind))
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.surface, in: Capsule())
            }
            Spacer()
        }
    }

    private func playButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if isResolving {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.fill")
                }
                Text(isResolving ? "Loading…" : label)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .disabled(isResolving)
    }

    private var epgSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Program Guide").font(.headline)
            ForEach(epg.prefix(6)) { entry in
                HStack(alignment: .top) {
                    Text(entry.start, style: .time)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 54, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).font(.subheadline)
                        if let desc = entry.description, !desc.isEmpty {
                            Text(desc).font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var episodesSection: some View {
        if let detail, !detail.seasons.isEmpty {
            ForEach(detail.seasons.keys.sorted(), id: \.self) { season in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Season \(season)").font(.headline)
                    ForEach(detail.seasons[season] ?? []) { episode in
                        Button {
                            play(ref: episode.playbackRef, ext: episode.containerExtension)
                        } label: {
                            HStack {
                                Image(systemName: "play.circle")
                                VStack(alignment: .leading) {
                                    Text("E\(episode.episode) · \(episode.title)")
                                        .font(.subheadline)
                                    if let plot = episode.plot, !plot.isEmpty {
                                        Text(plot).font(.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else if detail == nil {
            ProgressView().frame(maxWidth: .infinity)
        } else {
            playButton(label: "Play") {
                play(ref: item.playbackRef, ext: item.containerExtension)
            }
        }
    }

    // MARK: - Actions

    private func loadDetails() async {
        guard let provider = store.selectedProvider else { return }
        let client = store.client(for: provider)
        if item.kind == .series {
            detail = try? await client.seriesDetail(for: item)
        }
        if item.kind == .live {
            epg = (try? await client.shortEPG(forChannelRef: item.playbackRef)) ?? []
        }
    }

    private func play(ref: String, ext: String?) {
        guard let provider = store.selectedProvider, !isResolving else { return }
        let client = store.client(for: provider)
        isResolving = true
        loadError = nil
        // Stay on the main actor: `playback` and `loadError` drive the UI.
        Task { @MainActor in
            defer { isResolving = false }
            do {
                let url = try await client.streamURL(
                    kind: item.kind,
                    playbackRef: ref,
                    containerExtension: ext
                )
                playback = PlaybackRequest(url: url, title: item.name, headers: client.streamHeaders)
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}

extension View {
    @ViewBuilder
    func fullScreenCoverCompat<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(macOS)
        self.sheet(item: item, content: content)
        #else
        self.fullScreenCover(item: item, content: content)
        #endif
    }
}
