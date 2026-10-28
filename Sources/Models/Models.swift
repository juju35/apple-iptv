import Foundation

// MARK: - Provider

/// An IPTV provider account (Xtream Codes or Stalker/MAC portal).
struct Provider: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case xtream
        case stalker

        var id: String { rawValue }

        var label: String {
            switch self {
            case .xtream: return "Xtream Codes"
            case .stalker: return "Stalker (MAC)"
            }
        }
    }

    var id: UUID = UUID()
    var name: String
    var kind: Kind
    /// Base URL of the portal, e.g. `http://host:8080` (Xtream) or `http://host/stalker_portal` (Stalker).
    var serverURL: String

    // Xtream credentials
    var username: String = ""
    var password: String = ""

    // Stalker credentials
    var macAddress: String = ""

    var baseURL: URL? { URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) }
}

// MARK: - Content

struct ContentCategory: Identifiable, Hashable {
    let id: String
    let name: String
}

enum MediaKind: String, Hashable {
    case live
    case movie
    case series
}

/// Unified media item across both protocols.
struct MediaItem: Identifiable, Hashable {
    let id: String
    let kind: MediaKind
    let name: String
    let posterURL: URL?
    let categoryId: String?
    /// Xtream: stream/vod/series id. Stalker: channel `cmd` or VOD id.
    let playbackRef: String
    /// Container extension for Xtream VOD (mp4, mkv…).
    let containerExtension: String?
    var rating: Double?
    var plot: String?
    var year: String?

    init(
        id: String,
        kind: MediaKind,
        name: String,
        posterURL: URL? = nil,
        categoryId: String? = nil,
        playbackRef: String,
        containerExtension: String? = nil,
        rating: Double? = nil,
        plot: String? = nil,
        year: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.posterURL = posterURL
        self.categoryId = categoryId
        self.playbackRef = playbackRef
        self.containerExtension = containerExtension
        self.rating = rating
        self.plot = plot
        self.year = year
    }
}

struct Episode: Identifiable, Hashable {
    let id: String
    let title: String
    let season: Int
    let episode: Int
    let plot: String?
    let posterURL: URL?
    /// Playback reference (Xtream episode id + extension, Stalker cmd).
    let playbackRef: String
    let containerExtension: String?
}

struct SeriesDetail {
    let item: MediaItem
    let seasons: [Int: [Episode]]
}

/// Which media engine renders a stream.
enum PlaybackEngine {
    /// AVFoundation: HLS and MP4-family containers, native AirPlay / PiP.
    case system
    /// VLCKit: everything else (MKV, AVI, raw MPEG-TS, …).
    case vlc

    /// Extensions AVFoundation handles well; anything else goes to VLC.
    private static let systemExtensions: Set<String> = ["m3u8", "mp4", "m4v", "mov"]

    /// Picks the engine from the URL: the path extension, or a container hint in
    /// query values (Stalker uses `stream=123.mkv`).
    static func preferred(for url: URL) -> PlaybackEngine {
        var candidates = [url.pathExtension.lowercased()]
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            candidates += items.compactMap { item in
                guard let value = item.value, value.contains(".") else { return nil }
                return value.components(separatedBy: ".").last?.lowercased()
            }
        }
        return candidates.contains { systemExtensions.contains($0) } ? .system : .vlc
    }
}

/// Everything the player needs to start a stream.
struct PlaybackRequest: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    /// Extra HTTP headers for the media requests (currently only `User-Agent` is honoured).
    var headers: [String: String] = [:]
    /// Engine to start with; the player falls back to VLC if the system player fails.
    var engine: PlaybackEngine
    /// Where to save watch progress; nil for live TV.
    var progress: PlaybackProgressContext?
    /// Seconds to resume from.
    var startPosition: Double = 0

    init(url: URL, title: String, headers: [String: String] = [:], engine: PlaybackEngine? = nil) {
        self.url = url
        self.title = title
        self.headers = headers
        self.engine = engine ?? PlaybackEngine.preferred(for: url)
    }
}

struct EPGEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let description: String?
}

// MARK: - Errors

enum IPTVError: LocalizedError {
    case invalidURL
    case badResponse(Int)
    case authenticationFailed(String)
    case decoding(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid portal URL."
        case .badResponse(let code): return "Server returned HTTP \(code)."
        case .authenticationFailed(let reason): return "Authentication failed: \(reason)"
        case .decoding(let context): return "Unexpected server payload (\(context))."
        case .unsupported(let what): return "\(what) is not supported by this provider."
        }
    }
}
