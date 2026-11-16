import Foundation
import Testing
@testable import BMusicCore

struct TrackDragPayloadTests {
    @Test func dragBytesDecodeAndAddExactlyOnce() throws {
        let track = Track(bvid: "BVdrag", cid: 42, title: "拖放曲目", uploader: "Artist", part: 2)
        let bytes = try TrackDragPayload(track: track).encoded()
        let received = try TrackDragPayload.decode(bytes)
        #expect(received == track)
        var library = Library()
        let playlist = Playlist(name: "Drop target")
        library.playlists = [playlist]
        library.add(received, to: playlist.id)
        library.add(received, to: playlist.id)
        #expect(library.playlists[0].tracks == [track])
    }
    @Test func rejectsMalformedOrOversizedDrops() {
        #expect(throws: (any Error).self) { try TrackDragPayload.decode(Data("{}".utf8)) }
        #expect(throws: (any Error).self) { try TrackDragPayload.decode(Data(count: 256 * 1024 + 1)) }
    }
}
