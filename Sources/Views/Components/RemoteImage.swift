import ImageIO
import SwiftUI

/// Loads, downsamples and caches artwork. `AsyncImage` re-downloads and decodes full-size posters
/// every time a lazy grid cell comes back on screen, which made scrolling crawl on Apple TV.
actor ImageLoader {
    static let shared = ImageLoader()

    /// NSCache is thread-safe; read without hopping onto the actor so a cached poster shows at once.
    nonisolated(unsafe) private let cache = NSCache<NSString, CGImageBox>()
    private var inFlight: [String: Task<CGImage?, Never>] = [:]
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 256 << 20)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()

    init() {
        cache.countLimit = 600
    }

    nonisolated func cached(_ url: URL, maxPixelSize: Int) -> CGImage? {
        cache.object(forKey: Self.key(url, maxPixelSize) as NSString)?.image
    }

    func image(for url: URL, maxPixelSize: Int) async -> CGImage? {
        let key = Self.key(url, maxPixelSize)
        if let hit = cache.object(forKey: key as NSString) { return hit.image }
        if let task = inFlight[key] { return await task.value }
        let session = session
        let task = Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let (data, _) = try? await session.data(from: url) else { return nil }
            return Self.downsample(data, maxPixelSize: maxPixelSize)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { cache.setObject(CGImageBox(image), forKey: key as NSString) }
        return image
    }

    nonisolated private static func key(_ url: URL, _ size: Int) -> String { "\(size)|\(url.absoluteString)" }

    /// Decodes straight to the displayed size, off the main thread.
    private static func downsample(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

final class CGImageBox: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

/// `AsyncImage` replacement backed by `ImageLoader`: cached, downsampled to `maxPixelSize`.
struct RemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    var maxPixelSize = 600
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image = image ?? url.flatMap({ ImageLoader.shared.cached($0, maxPixelSize: maxPixelSize) }) {
                content(Image(decorative: image, scale: 1))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            image = await ImageLoader.shared.image(for: url, maxPixelSize: maxPixelSize)
        }
    }
}
