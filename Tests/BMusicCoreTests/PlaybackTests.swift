import AppKit
import MediaPlayer
import Testing
@testable import BMusicCore

struct PlaybackTests {
    @Test func scrubbingAndStaleSeekCompletion() {
        var position = PlaybackPosition()
        position.reset(duration: 10800)
        position.tick(30)
        position.scrub(to: 3600)
        position.tick(31)
        #expect(position.displayed == 3600)
        let first = position.seek(to: 3600)
        position.tick(32)
        #expect(position.displayed == 3600)
        let second = position.seek(to: 7200)
        let stale = position.complete(first, actual: 3600)
        #expect(!stale)
        #expect(position.displayed == 7200)
        let latest = position.complete(second, actual: 7200.1)
        #expect(latest)
        position.tick(7201)
        #expect(position.displayed == 7201)
    }
    @Test func scrubbingDuringPendingSeekAndTrackChange() {
        var position = PlaybackPosition()
        position.reset(duration: 10800)
        let pending = position.seek(to: 1000)
        position.scrub(to: 4000)
        let completed = position.complete(pending, actual: 1000)
        #expect(completed)
        #expect(position.displayed == 4000)
        position.cancelScrub()
        #expect(position.displayed == 1000)
        let old = position.seek(to: 8000)
        position.reset(duration: 120)
        let stale = position.complete(old, actual: 8000)
        #expect(!stale)
        position.scrub(to: 999)
        #expect(position.displayed == 120)
        position.seek(to: .nan)
        #expect(position.displayed == 0)
    }
    @MainActor @Test func artworkSurvivesClockUpdatesAndTrackChanges() async throws {
        var snapshot: [String: Any]?
        var state: MPNowPlayingPlaybackState = .unknown
        let image = NSImage(size: NSSize(width: 200, height: 200))
        let publisher = NowPlayingPublisher(artworkLoader: { _ in image }, publish: { snapshot = $0; state = $1 })
        let track = Track(bvid: "BV1", title: "Cover test", uploader: "Artist", cover: URL(string: "https://example.com/cover.jpg"), duration: 100)
        publisher.setTrack(track)
        for _ in 0..<20 {
            if snapshot?[MPMediaItemPropertyArtwork] != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let artwork = try #require(snapshot?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork)
        publisher.update(elapsed: 42, duration: 100, playing: true, force: true)
        #expect((snapshot?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork) === artwork)
        #expect(snapshot?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 42)
        #expect(state == .playing)
        publisher.update(elapsed: 42, duration: 100, playing: false, force: true)
        #expect(state == .paused)
        publisher.setTrack(Track(bvid: "BV2", title: "Next", uploader: "Other"))
        #expect(snapshot?[MPMediaItemPropertyArtwork] == nil)
        #expect(snapshot?[MPMediaItemPropertyTitle] as? String == "Next")
        publisher.clear()
        #expect(snapshot == nil)
    }
    @MainActor @Test func staleArtworkCannotReplaceNewTrack() async throws {
        var continuation: CheckedContinuation<NSImage, Error>?
        var snapshot: [String: Any]?
        let publisher = NowPlayingPublisher(artworkLoader: { _ in
            try await withCheckedThrowingContinuation { continuation = $0 }
        }, publish: { value, _ in snapshot = value })
        publisher.setTrack(Track(bvid: "old", title: "Old", uploader: "", cover: URL(string: "https://example.com/old.jpg")))
        for _ in 0..<20 {
            if continuation != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let pending = try #require(continuation)
        publisher.setTrack(Track(bvid: "new", title: "New", uploader: ""))
        pending.resume(returning: NSImage(size: NSSize(width: 100, height: 100)))
        await Task.yield()
        #expect(snapshot?[MPMediaItemPropertyTitle] as? String == "New")
        #expect(snapshot?[MPMediaItemPropertyArtwork] == nil)
    }
}
