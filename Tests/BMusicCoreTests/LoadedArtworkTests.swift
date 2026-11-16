import AppKit
import Testing
@testable import BMusicCore

struct LoadedArtworkTests {
    @Test func retainsLargestLiveVariantForReuse() {
        let loaded = LoadedArtwork()
        let url = URL(string: "https://example.com/variants.jpg")!
        let large = NSImage(size: NSSize(width: 600, height: 600))
        let small = NSImage(size: NSSize(width: 160, height: 160))
        loaded.record(large, for: url)
        loaded.record(small, for: url)
        #expect(loaded.image(for: url) === large)
        withExtendedLifetime((large, small)) {}
    }
    @Test func largerLoadedCoverSatisfiesSmallRequestWithoutNetwork() async throws {
        let service = ArtworkService()
        let url = URL(string: "https://fixture.invalid/already-loaded.jpg")!
        let image = NSImage(size: NSSize(width: 600, height: 600))
        service.loaded.record(image, for: url)
        let reused = try await service.image(url, pixels: 160)
        #expect(reused === image)
        withExtendedLifetime(image) {}
    }
    @Test func reusesExactImageWithoutRetainingDecodedMemory() {
        let loaded = LoadedArtwork()
        let url = URL(string: "https://example.com/cover.jpg")!
        weak var released: NSImage?
        autoreleasepool {
            let image = NSImage(size: NSSize(width: 160, height: 160))
            released = image
            loaded.record(image, for: url)
            #expect(loaded.image(for: url) === image)
            #expect(loaded.image(for: nil) == nil)
        }
        #expect(released == nil)
        #expect(loaded.image(for: url) == nil)
    }
}
