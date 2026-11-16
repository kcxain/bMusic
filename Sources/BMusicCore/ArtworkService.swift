import AppKit
import ImageIO

public struct DecodedArtwork: @unchecked Sendable {
    public let image: NSImage
    public let cost: Int
}

/// Shared by cards and system metadata. Decoding executes off the main actor.
public final class ArtworkService: Sendable {
    private struct Key: Hashable, Sendable { let url: URL; let pixels: Int }
    public static let shared = ArtworkService()
    public let loaded = LoadedArtwork()
    private let pool = ResourcePool<Key, DecodedArtwork>(concurrency: 3, budget: 8 * 1024 * 1024,
                                                       countLimit: 80, lifetime: 1800, cost: { $0.cost })
    private let session: URLSession
    public init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 512 * 1024, diskCapacity: 48 * 1024 * 1024, diskPath: "BMusic-artwork")
        config.timeoutIntervalForRequest = 12
        config.httpMaximumConnectionsPerHost = 3
        self.session = URLSession(configuration: config)
    }
    public func image(_ url: URL, pixels: Int = 400, priority: Int = 0) async throws -> NSImage {
        let size = pixels <= 160 ? 160 : (pixels <= 400 ? 400 : 600)
        try Task.checkCancellation()
        if let image = loaded.image(for: url), min(image.size.width, image.size.height) >= CGFloat(size) {
            return image
        }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let host = url.host, host == "hdslb.com" || host.hasSuffix(".hdslb.com"), parts?.path.contains("@") == false {
            parts?.path += "@\(size)w_\(size)h_1c.jpg"
        }
        let target = parts?.url ?? url, session = session
        let result = try await pool.value(for: Key(url: target, pixels: size), priority: priority) {
            var request = URLRequest(url: target)
            request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 8 * 1024 * 1024,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: size,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw BMusicError.invalidResponse }
            return DecodedArtwork(image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)),
                                  cost: cg.bytesPerRow * cg.height)
        }
        try Task.checkCancellation()
        loaded.record(result.image, for: url)
        return result.image
    }
    public func trim() async { await pool.clear() }
}
