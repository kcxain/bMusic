import Testing
import AVFoundation
import MediaPlayer
@testable import BMusicCore

struct LiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BMUSIC_LIVE_TESTS"] == "1")) func testLiveSearchAndAudioPlayback() async throws {
        guard ProcessInfo.processInfo.environment["BMUSIC_LIVE_TESTS"] == "1" else { return }
        let started = Date()
        let client = BilibiliClient()
        if ProcessInfo.processInfo.environment["BMUSIC_AUDIO_ONLY"] != "1" {
            let qr = try await client.generateQR()
            #expect(qr.url.hasPrefix("https://")); #expect(!(qr.key.isEmpty))
            let search = try await client.search("Never Gonna Give You Up", musicOnly: false)
            #expect(!(search.tracks.isEmpty))
        }
        print("Live stage: resolving video details")
        let details = try await client.details(Track(bvid: ProcessInfo.processInfo.environment["BMUSIC_TEST_BVID"] ?? "BV1GJ411x7h7", title: "test", uploader: ""))
        print("Live stage: downloading artwork")
        try await verifyArtwork(details.tracks[0])
        print("Live stage: requesting audio streams")
        let streams = try await client.audio(details.tracks[0])
        let stream = try #require(AudioStream.preferred(in: streams, hiRes: true))
        print("Live API: parts=\(details.tracks.count), audio=\(streams.map(\.id)), selected=\(stream.detail)")
        var lastError: Error?
        for url in [stream.url] + stream.backups {
            do {
                let source = try await IndexedAudioAsset.prepare(url: url)
                let asset = source.asset
                print("Asset begins at \(Date().timeIntervalSince(started))s")
                let duration = try await asset.load(.duration)
                #expect(duration.seconds > 100)
                print("Metadata ready at \(Date().timeIntervalSince(started))s")
                let played = try await verifyPlayback(asset)
                print("Playback and seek ready at \(Date().timeIntervalSince(started))s")
                #expect(played > 0.1)
                withExtendedLifetime(source) {}
                print("Playable CDN: \(url.host ?? "")")
                return
            } catch { lastError = error; print("CDN failed: \(url.host ?? ""), \((error as NSError).code)") }
        }
        throw lastError ?? BMusicError.noAudio
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BMUSIC_LIVE_TESTS"] == "1")) func musicRankingLoadsRealCovers() async throws {
        let tracks = try await BilibiliClient().musicRanking()
        #expect(!tracks.isEmpty)
        #expect(tracks.count <= 12)
        #expect(tracks.allSatisfy { !$0.title.isEmpty && $0.cover != nil })
        #expect(Set(tracks.map(\.id)).count == tracks.count)
        print("Music ranking loaded: \(tracks.count) tracks")
    }
    @MainActor private func verifyArtwork(_ track: Track) async throws {
        var snapshot: [String: Any]?
        let publisher = NowPlayingPublisher(publish: { value, _ in snapshot = value })
        publisher.setTrack(track)
        for _ in 0..<80 {
            if let artwork = snapshot?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork {
                #expect(artwork.bounds.width > 0)
                publisher.update(elapsed: 20, duration: track.duration, playing: true, force: true)
                #expect(snapshot?[MPMediaItemPropertyArtwork] != nil)
                print("Real cover decoded and retained in system metadata: \(artwork.bounds.size)")
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        Issue.record("Cover failed to load into now-playing metadata")
    }
    @MainActor private func verifyPlayback(_ asset: AVURLAsset) async throws -> Double {
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.volume = 0
        player.play()
        defer { player.pause(); player.replaceCurrentItem(with: nil) }
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(500))
            if let error = player.currentItem?.error { throw error }
            if player.currentTime().seconds > 0.1 {
                let mediaTypes = player.currentItem?.tracks.compactMap { $0.assetTrack?.mediaType } ?? []
                #expect(mediaTypes.contains(.audio))
                #expect(!mediaTypes.contains(.video))
                print("Live AVPlayer: advanced=\(player.currentTime().seconds)s, audio-only=true")
                let beforeSeek = player.currentTime().seconds
                let total = player.currentItem?.duration.seconds ?? 120
                let targets = total > 3600 ? [60.0, total * 0.75, 60.0] : [60.0]
                for target in targets {
                    let started = Date()
                    player.pause()
                    let tolerance = CMTime(seconds: 0.25, preferredTimescale: 600)
                    let done = await player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance)
                    #expect(done)
                    #expect(abs(player.currentTime().seconds - target) < 0.5)
                    try await Task.sleep(for: .milliseconds(200))
                    #expect(player.rate == 0)
                    player.play()
                    var advanced = false
                    for _ in 0..<60 {
                        try await Task.sleep(for: .milliseconds(250))
                        if player.currentTime().seconds >= target + 0.1 {
                            advanced = true
                            print("Seek target=\(target)s, completed and resumed in \(Date().timeIntervalSince(started))s")
                            break
                        }
                        if let error = player.currentItem?.error { throw error }
                    }
                    #expect(advanced)
                }
                return beforeSeek
            }
        }
        Issue.record("AVPlayer did not advance within 30 seconds")
        return 0
    }
}
