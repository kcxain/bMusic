import AppKit

/// An index into images already owned by views/cache; adds no decoded-image retention.
public final class LoadedArtwork: @unchecked Sendable {
    private final class Reference {
        weak var image: NSImage?
        init(_ image: NSImage) { self.image = image }
    }
    private let lock = NSLock()
    private var images: [URL: Reference] = [:]
    public init() {}
    public func image(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        lock.lock(); defer { lock.unlock() }
        return images[url]?.image
    }
    public func record(_ image: NSImage, for url: URL) {
        lock.lock(); defer { lock.unlock() }
        if let existing = images[url]?.image,
           min(existing.size.width, existing.size.height) >= min(image.size.width, image.size.height) { return }
        // Prune only at capacity; registering a cached image stays O(1) normally.
        if images.count >= 160 { images = images.filter { $0.value.image != nil } }
        if images.count >= 160, images[url] == nil, let key = images.keys.first { images[key] = nil }
        images[url] = Reference(image)
    }
}
