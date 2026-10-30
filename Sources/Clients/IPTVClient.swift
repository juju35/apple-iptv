import Foundation

/// Protocol-agnostic interface implemented by both Xtream and Stalker clients.
protocol IPTVClient {
    func authenticate() async throws
    func categories(for kind: MediaKind) async throws -> [ContentCategory]
    func items(kind: MediaKind, categoryId: String?) async throws -> [MediaItem]
    func seriesDetail(for item: MediaItem) async throws -> SeriesDetail
    /// Resolves the final playable URL for an item or episode playback reference.
    func streamURL(kind: MediaKind, playbackRef: String, containerExtension: String?) async throws -> URL
    func shortEPG(forChannelRef ref: String) async throws -> [EPGEntry]
    /// Expiry date and limits of the account.
    func accountInfo() async throws -> AccountInfo
    /// The whole programme guide around now, by `MediaItem.id` of `channels`; empty when the
    /// provider has none (per-channel `shortEPG` is used then).
    func fullEPG(for channels: [MediaItem]) async throws -> [String: [EPGEntry]]
    /// HTTP headers the player should send when fetching the stream (e.g. a portal-specific User-Agent).
    var streamHeaders: [String: String] { get }
    /// Called every 30 seconds while something plays: Stalker portals cut the stream of a box that
    /// stops reporting in.
    func keepAlive() async
}

extension IPTVClient {
    var streamHeaders: [String: String] { [:] }

    func keepAlive() async {}

    func fullEPG(for channels: [MediaItem]) async throws -> [String: [EPGEntry]] { [:] }
}

/// The part of the guide worth keeping: from 2 hours ago to 2 days ahead.
enum EPGWindow {
    static var current: ClosedRange<Date> {
        Date().addingTimeInterval(-2 * 3600)...Date().addingTimeInterval(48 * 3600)
    }
}

enum IPTVClientFactory {
    static func client(for provider: Provider) -> IPTVClient {
        switch provider.kind {
        case .xtream: return XtreamClient(provider: provider)
        case .stalker: return StalkerClient(provider: provider)
        }
    }
}

extension URLSession {
    static let iptv: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["User-Agent": "AppleIPTV/1.0"]
        return URLSession(configuration: config)
    }()
}
