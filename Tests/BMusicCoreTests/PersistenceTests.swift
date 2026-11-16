import Foundation
import Testing
@testable import BMusicCore

struct PersistenceTests {
    @Test func latestRevisionWinsAndFailureCanRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(url: directory.appendingPathComponent("library.json"))
        let writer = LibraryPersistence(store: store)
        var old = Library(), latest = Library()
        old.record(Track(bvid: "old", title: "Old", uploader: ""))
        latest.record(Track(bvid: "new", title: "New", uploader: ""))
        await writer.stage(latest, revision: 2)
        await writer.stage(old, revision: 1)
        // A file in the directory's position forces a real disk failure.
        try Data([1]).write(to: directory)
        do { try await writer.flush(); Issue.record("Expected write failure") } catch { }
        try FileManager.default.removeItem(at: directory)
        try await writer.flush()
        #expect(try store.load() == latest)
        await writer.stage(old, revision: 1)
        try await writer.flush()
        #expect(try store.load() == latest)
    }
    @Test func duplicateQueueEntriesHaveStableDistinctIdentity() {
        let track = Track(bvid: "same", title: "Track", uploader: "")
        var entries = [QueueEntry(track: track), QueueEntry(track: track)]
        let id = entries[1].id
        entries[1].track.cid = 123
        #expect(entries[0].id != entries[1].id)
        #expect(entries[1].id == id)
        #expect(entries[0].track.cid == nil)
    }
    @Test func chartSnapshotIsBoundedAndRoundTrips() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DiscoveryCache(url: directory.appendingPathComponent("chart.json"))
        let tracks = (0..<30).map { Track(bvid: "BV\($0)", title: "Track", uploader: "") }
        await cache.save(tracks)
        #expect(await cache.load() == Array(tracks.prefix(12)))
    }
}
