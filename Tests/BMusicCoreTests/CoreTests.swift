import Foundation
import Testing
@testable import BMusicCore

struct CoreTests {
    @Test func testWBIKnownVector() throws {
        let result = try WBISigner.query(["foo": "114", "bar": "514", "baz": "1919810"], imageKey: "7cd084941338484aae1ad9425b84077c", subKey: "4932caff0ff746eab6f01bf08b70ac45", timestamp: 1702204169)
        #expect(result == "bar=514&baz=1919810&foo=114&wts=1702204169&w_rid=6149fdadf571698ca7e6a567265cd0ee")
    }
    @Test func testWBIEncoding() throws {
        let result = try WBISigner.query(["keyword": "音乐 !'()*&"], imageKey: "7cd084941338484aae1ad9425b84077c", subKey: "4932caff0ff746eab6f01bf08b70ac45", timestamp: 1)
        #expect(result.hasPrefix("keyword=%E9%9F%B3%E4%B9%90%20%26&wts=1&"))
        #expect(throws: (any Error).self) { try WBISigner.query([:], imageKey: "short", subKey: "bad") }
    }
    @Test func dolbyTrackPreservesCodecAndDoesNotPromiseSpatialOutput() throws {
        let streams = try BilibiliClient.parseAudio(["dash": [
            "dolby": ["audio": [["id": 30250, "baseUrl": "https://example.com/dolby.m4s", "codecs": "ec-3", "bandwidth": 384000]]]
        ]])
        #expect(streams.count == 1)
        #expect(streams[0].codec == "ec-3")
        #expect(streams[0].label == "Dolby 音轨")
    }
    @Test func testAudioParsingAndPreference() throws {
        let streams = try BilibiliClient.parseAudio(["dash": [
            "audio": [["id": 30280, "baseUrl": "https://example.com/a.m4s", "bandwidth": 192000, "codecs": "mp4a.40.2"], ["id": 30216, "base_url": "https://example.com/b.m4s", "bandwidth": 64000]],
            "flac": ["audio": ["id": 30251, "base_url": "https://example.com/c.m4s", "bandwidth": 900000, "codecs": "fLaC", "backup_url": ["https://example.com/backup.m4s"]]],
            "dolby": ["audio": NSNull()],
            "video": [["id": 80, "baseUrl": "https://example.com/video.m4s"]]
        ]])
        #expect(streams.count == 3)
        #expect(AudioStream.preferred(in: streams, hiRes: true)?.id == 30251)
        #expect(AudioStream.preferred(in: streams, hiRes: false)?.id == 30280)
        #expect(streams[0].backups.count == 1)
        #expect(throws: (any Error).self) { try BilibiliClient.parseAudio(["durl": []]) }
    }
    @Test func testLibraryRoundTripAndDeduplication() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LibraryStore(url: dir.appendingPathComponent("library.json"))
        var library = try store.load()
        let one = Track(bvid: "BV1GJ411x7h7", title: "One", uploader: "Artist")
        let two = Track(bvid: one.bvid, title: "Part two", uploader: "Artist", part: 2)
        library.toggleFavorite(one); library.toggleFavorite(two)
        #expect(library.favorites.count == 2)
        library.toggleFavorite(one); #expect(library.favorites == [two])
        let playlist = Playlist(name: "晚间")
        library.playlists.append(playlist)
        library.add(one, to: playlist.id); library.add(one, to: playlist.id)
        #expect(library.playlists[0].tracks.count == 1)
        library.record(one); library.record(two); library.record(one)
        #expect(library.recent == [one, two])
        try store.save(library); #expect(try store.load() == library)
    }
    @Test func testCorruptLibraryIsPreserved() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("broken json".utf8); try original.write(to: url)
        #expect(throws: (any Error).self) { try LibraryStore(url: url).load() }
        #expect(try Data(contentsOf: url) == original)
    }
    @Test func testTextFormatting() {
        #expect(TextFormatting.cleanTitle("<em class=\"keyword\">音乐</em> &amp; Live") == "音乐 & Live")
        #expect(TextFormatting.seconds("1:02:03") == 3723)
        #expect(TextFormatting.time(3723) == "1:02:03")
        #expect(TextFormatting.time(.nan) == "0:00")
    }
}
