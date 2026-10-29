import Foundation

extension AppStore {
    /// Unfinished progress for a movie or an episode.
    func progress(for key: String) -> PlaybackProgress? {
        playbackProgress[key].flatMap { $0.isResumable ? $0 : nil }
    }

    /// Whether a movie or episode was watched to the end.
    func isWatched(_ key: String) -> Bool {
        playbackProgress[key]?.isFinished == true
    }

    /// The most recently watched, unfinished episode of a series.
    func latestEpisodeProgress(forSeries itemId: String) -> PlaybackProgress? {
        playbackProgress.values
            .filter { $0.itemId == itemId && $0.episodeId != nil && $0.isResumable }
            .max { $0.updatedAt < $1.updatedAt }
    }

    /// Started movies and series, most recent first (`kind` nil for both).
    func continueWatching(_ kind: MediaKind?) -> [ContinueWatchingEntry] {
        var seen: Set<String> = []
        return playbackProgress.values
            .filter(\.isResumable)
            .sorted { $0.updatedAt > $1.updatedAt }
            .compactMap { progress in
                guard let item = visibleItemsById[progress.itemId], kind == nil || item.kind == kind,
                      seen.insert(item.id).inserted else { return nil }
                return ContinueWatchingEntry(item: item, progress: progress)
            }
    }

    /// Drops a movie or series (all its episodes) from Continue Watching, on every device: the entries stay,
    /// marked, so the iCloud merge doesn't bring them back. Playing it again starts a new entry.
    func removeFromContinueWatching(_ item: MediaItem) {
        let now = Date()
        for (key, entry) in playbackProgress where entry.itemId == item.id && entry.isResumable {
            var dismissed = entry
            dismissed.isDismissed = true
            dismissed.updatedAt = now
            playbackProgress[key] = dismissed
        }
        progressSync.save(Array(playbackProgress.values))
    }

    /// Saves where playback is; called periodically by the players and when they close.
    func recordProgress(_ context: PlaybackProgressContext, position: Double, duration: Double) {
        // Live streams and unknown durations have nothing to resume.
        guard !Demo.isOn, position.isFinite, duration.isFinite, duration > 60 else { return }
        let existing = playbackProgress[context.key]
        // Barely started: not worth a Continue Watching entry.
        guard position >= 10 || existing != nil else { return }
        playbackProgress[context.key] = PlaybackProgress(
            key: context.key,
            itemId: context.itemId,
            episodeId: context.episodeId,
            season: context.season,
            episode: context.episode,
            position: position,
            duration: duration,
            updatedAt: Date(),
            isFinished: position / duration >= 0.95
        )
        playbackProgress = PlaybackProgress.pruned(playbackProgress)
        progressSync.save(Array(playbackProgress.values))
    }
}
