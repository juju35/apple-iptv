import Foundation

/// Protocol-agnostic interface implemented by both Xtream and Stalker clients.
protocol IPTVClient {
    var provider: Provider { get }

    func authenticate() async throws
    func categories(for kind: MediaKind) async throws -> [ContentCategory]
    func items(kind: MediaKind, categoryId: String?) async throws -> [MediaItem]
    func seriesDetail(for item: MediaItem) async throws -> SeriesDetail
    /// Resolves the final playable URL for an item or episode playback reference.
    func streamURL(kind: MediaKind, playbackRef: String, containerExtension: String?) async throws -> URL
    func shortEPG(forChannelRef ref: String) async throws -> [EPGEntry]
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
