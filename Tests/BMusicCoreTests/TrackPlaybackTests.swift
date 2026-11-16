import Testing
@testable import BMusicCore

struct TrackPlaybackTests {
    @Test func sameTrackAcrossSourcesTogglesAndDifferentPartsStart() {
        let recent = Track(bvid: "BV1", cid: 123, title: "Resolved", uploader: "Uploader")
        let search = Track(bvid: "BV1", title: "Search title", uploader: "Uploader")
        let favorite = recent
        for track in [recent, search, favorite] {
            let state = TrackPlaybackState(trackID: track.id, currentID: recent.id, intendsPlayback: true, failed: false)
            #expect(state == .playing)
            #expect(state.shouldToggle)
            #expect(state.symbol == "pause.fill")
            let paused = TrackPlaybackState(trackID: track.id, currentID: recent.id, intendsPlayback: false, failed: false)
            #expect(paused == .paused)
            #expect(paused.symbol == "play.fill")
        }
        let part = Track(bvid: "BV1", title: "P2", uploader: "Uploader", part: 2)
        let state = TrackPlaybackState(trackID: part.id, currentID: recent.id, intendsPlayback: true, failed: false)
        #expect(state == .idle)
        #expect(!state.shouldToggle)
        let failed = TrackPlaybackState(trackID: recent.id, currentID: recent.id, intendsPlayback: true, failed: true)
        #expect(failed == .failed)
        #expect(!failed.shouldToggle)
    }
}
