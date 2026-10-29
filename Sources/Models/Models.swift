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

struct ContentCategory: Identifiable, Hashable, Codable {
    let id: String
    let name: String
}

enum MediaKind: String, Hashable, Codable {
    case live
    case movie
    case series
}

/// Unified media item across both protocols.
struct MediaItem: Identifiable, Hashable, Codable {
    let id: String
    let kind: MediaKind
    let name: String
    let posterURL: URL?
    let categoryId: String?
    /// Further categories of an item listed in several (Xtream `category_ids`).
    var otherCategoryIds: [String]?
    /// The channel's id in the provider's XMLTV guide (Xtream `epg_channel_id`).
    var epgChannelId: String?
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
        year: String? = nil,
        otherCategoryIds: [String]? = nil,
        epgChannelId: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.posterURL = posterURL
        self.categoryId = categoryId
        self.otherCategoryIds = otherCategoryIds
        self.epgChannelId = epgChannelId
        self.playbackRef = playbackRef
        self.containerExtension = containerExtension
        self.rating = rating
        self.plot = plot
        self.year = year
    }
}

extension MediaItem {
    /// Every category the item is listed in, the main one first.
    var categoryIds: [String] {
        (categoryId.map { [$0] } ?? []) + (otherCategoryIds ?? [])
    }

    func belongs(to category: String) -> Bool {
        categoryId == category || otherCategoryIds?.contains(category) == true
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
    /// Poster, episode still or channel logo of what plays (iPhone Duo controls).
    var artworkURL: URL?
    /// The live channel playing, and the list it was started from, for zapping.
    var channel: MediaItem?
    var channelList: [MediaItem] = []

    init(url: URL, title: String, headers: [String: String] = [:], engine: PlaybackEngine? = nil) {
        self.url = url
        self.title = title
        self.headers = headers
        self.engine = engine ?? PlaybackEngine.preferred(for: url)
    }
}

/// Subscription details of a provider account.
struct AccountInfo: Codable, Hashable {
    /// nil with `isUnlimited` false: the provider doesn't say.
    var expiresAt: Date?
    var isUnlimited = false
    var maxConnections: Int?

    /// Parses the date formats portals use ("2026-12-31 23:59:59", "2026-12-31",
    /// "December 31, 2026, 11:59 pm", or a Unix timestamp).
    static func date(from value: Any?) -> Date? {
        guard let value else { return nil }
        let text = "\(value)".trimmingCharacters(in: .whitespaces)
        if let seconds = Double(text) {
            // Years 2000…2100 only, so a phone number isn't taken for a timestamp.
            return (946_684_800...4_102_444_800).contains(seconds) ? Date(timeIntervalSince1970: seconds) : nil
        }
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd", "MMMM d, yyyy, h:mm a",
                       "MMMM d, yyyy", "dd.MM.yyyy", "dd/MM/yyyy"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

struct EPGEntry: Identifiable, Hashable, Codable {
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
        case .invalidURL: return String(localized: "Invalid portal URL.")
        case .badResponse(let code): return String(localized: "Server returned HTTP \(code).")
        case .authenticationFailed(let reason): return String(localized: "Authentication failed: \(reason)")
        case .decoding(let context): return String(localized: "Unexpected server payload (\(context)).")
        case .unsupported(let what): return String(localized: "\(what) is not supported by this provider.")
        }
    }
}
