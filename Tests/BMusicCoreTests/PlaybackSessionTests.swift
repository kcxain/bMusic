import Foundation
import Testing
@testable import BMusicCore

struct PlaybackSessionTests {
    @Test func unchangedSnapshotDoesNotRewriteFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("playback.json")
        let store = PlaybackSessionStore(url: url)
        let snapshot = PlaybackSession(tracks: [], currentTrackID: nil, elapsed: 0, mode: .sequential, volume: 0.8)
        try await store.save(snapshot, revision: 1)
        let sentinel = Date(timeIntervalSince1970: 1000)
        try FileManager.default.setAttributes([.modificationDate: sentinel], ofItemAtPath: url.path)
        try await store.save(snapshot, revision: 2)
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        #expect(modified == sentinel)
    }
    @Test func restoresQueueOrderPositionAndPreferences() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("playback.json")
        let one = Track(bvid: "BVone", cid: 42, title: "One", uploader: "Artist", duration: 10800)
        let two = Track(bvid: "BVtwo", title: "Two", uploader: "Artist")
        let snapshot = PlaybackSession(tracks: [two, one], currentTrackID: one.id, elapsed: 8179.25,
                                       mode: .repeatOne, volume: 0.45, qualityID: 30251)
        let store = PlaybackSessionStore(url: url)
        try await store.save(snapshot, revision: 2)
        try await store.save(PlaybackSession(tracks: [], currentTrackID: nil, elapsed: 0, mode: .sequential, volume: 1), revision: 1)
        #expect(try await PlaybackSessionStore(url: url).load() == snapshot)
        let empty = PlaybackSession(tracks: [], currentTrackID: nil, elapsed: 0, mode: .shuffle, volume: 0.5)
        try await store.save(empty, revision: 3)
        #expect(try await PlaybackSessionStore(url: url).load() == empty)
    }
    @Test func validatesStaleCurrentAndDuplicateTracks() throws {
        let track = Track(bvid: "BVone", title: "One", uploader: "", duration: 120)
        let valid = try PlaybackSession(tracks: [track, track], currentTrackID: track.id, elapsed: 500,
                                        mode: .sequential, volume: 2).validated()
        #expect(valid.tracks.count == 1)
        #expect(valid.elapsed == 120)
        #expect(valid.volume == 1)
        let missing = try PlaybackSession(tracks: [track], currentTrackID: "missing", elapsed: 50,
                                          mode: .shuffle, volume: -.infinity).validated()
        #expect(missing.currentTrackID == nil)
        #expect(missing.elapsed == 0)
        #expect(missing.volume == 0.8)
    }
    @Test func corruptFileIsPreserved() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data("corrupt".utf8)
        try bytes.write(to: url)
        do { _ = try await PlaybackSessionStore(url: url).load(); Issue.record("Expected decode failure") } catch { }
        #expect(try Data(contentsOf: url) == bytes)
    }
}
