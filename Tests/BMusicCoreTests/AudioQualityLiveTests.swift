import Testing
import AVFoundation
@testable import BMusicCore

struct AudioQualityLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BMUSIC_QUALITY_AUDIT"] == "1"))
    @MainActor func verifiesReturnedTracksThroughNativeDecoder() async throws {
        let client = BilibiliClient()
        try await client.restoreSession()
        let bvid = ProcessInfo.processInfo.environment["BMUSIC_TEST_BVID"] ?? "BV1krsE6WEGn"
        let track: Track
        if let keyword = ProcessInfo.processInfo.environment["BMUSIC_QUALITY_SEARCH"] {
            let results = try await client.search(keyword, musicOnly: false)
            track = try #require(results.tracks.first)
        } else { track = Track(bvid: bvid, title: "audit", uploader: "") }
        let details = try await client.details(track)
        let streams = try await client.audio(details.tracks[0])
        print("QUALITY_AUDIT returned IDs: \(streams.map(\.id))")
        for stream in streams {
            let source = try await IndexedAudioAsset.prepare(url: stream.url)
            // Compare one relayed fragment with the exact CDN byte range.
            var request = URLRequest(url: stream.url)
            request.setValue("bytes=0-262143", forHTTPHeaderField: "Range")
            request.setValue(BilibiliClient.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
            let config = URLSessionConfiguration.ephemeral; config.urlCache = nil
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            let head = try await BoundedHTTPData.load(session: session, request: request, limit: 262144) { $0.statusCode == 206 }
            let index = try SegmentIndex.parse(head)
            let segment = try #require(index.segments.first)
            request.setValue("bytes=\(segment.offset)-\(segment.offset + UInt64(segment.length) - 1)", forHTTPHeaderField: "Range")
            let original = try await BoundedHTTPData.load(session: session, request: request, limit: Int(segment.length)) { $0.statusCode == 206 }
            let localURL = source.asset.url.deletingLastPathComponent().appendingPathComponent("segment/0.m4s")
            let (relayed, _) = try await session.data(from: localURL)
            #expect(original == relayed)
            print("QUALITY_AUDIT \(stream.id) originalBytesPreserved=\(original == relayed)")
            let player = AVPlayer(playerItem: AVPlayerItem(asset: source.asset))
            player.volume = 0
            player.play()
            defer { player.pause(); player.replaceCurrentItem(with: nil); withExtendedLifetime(source) {} }
            var advanced = false
            for _ in 0..<80 {
                try await Task.sleep(for: .milliseconds(250))
                if let error = player.currentItem?.error { throw error }
                if player.currentTime().seconds > 0.25 { advanced = true; break }
            }
            #expect(advanced, "Native player failed to advance for \(stream.id)")
            print("QUALITY_AUDIT \(stream.id) codec=\(stream.codec) nativePlayback=\(advanced)")
            for track in player.currentItem?.tracks ?? [] {
                guard let assetTrack = track.assetTrack else { continue }
                let formats = try await assetTrack.load(.formatDescriptions)
                for format in formats {
                    if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                        print("QUALITY_AUDIT \(stream.id) sampleRate=\(asbd.mSampleRate) channels=\(asbd.mChannelsPerFrame) bits=\(asbd.mBitsPerChannel) format=\(asbd.mFormatID)")
                    }
                }
            }
        }
    }
}
