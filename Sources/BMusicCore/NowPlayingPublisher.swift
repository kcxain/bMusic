import AppKit
import ImageIO
import MediaPlayer

/// Owns system metadata and artwork; time updates retain the same artwork object.
@MainActor
public final class NowPlayingPublisher {
    public typealias ArtworkLoader = @MainActor (URL) async throws -> NSImage
    private let publish: ([String: Any]?, MPNowPlayingPlaybackState) -> Void
    private var state: MPNowPlayingPlaybackState = .paused
    private let loadArtwork: ArtworkLoader
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var info: [String: Any] = [:]
    private var lastClockUpdate = Date.distantPast
    private var lastPlaying = false
    private var artworkURL: URL?
    public init(artworkLoader: ArtworkLoader? = nil, publish: (([String: Any]?, MPNowPlayingPlaybackState) -> Void)? = nil) {
        self.publish = publish ?? { info, state in
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            MPNowPlayingInfoCenter.default().playbackState = state
        }
        self.loadArtwork = artworkLoader ?? { try await ArtworkService.shared.image($0, pixels: 600, priority: 10) }
    }
    public func setTrack(_ track: Track) {
        let sameArtwork = artworkURL == track.cover
        let existingArtwork = sameArtwork ? info[MPMediaItemPropertyArtwork] : nil
        if !sameArtwork { task?.cancel(); generation = UUID() }
        artworkURL = track.cover
        let token = generation
        info = [MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.uploader,
                MPMediaItemPropertyPlaybackDuration: track.duration,
                MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
                MPNowPlayingInfoPropertyPlaybackRate: 0.0,
                MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
                MPNowPlayingInfoPropertyIsLiveStream: false,
                MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
                MPNowPlayingInfoPropertyExternalContentIdentifier: track.id]
        if let existingArtwork { info[MPMediaItemPropertyArtwork] = existingArtwork }
        state = .paused; publish(info, state)
        lastClockUpdate = .distantPast; lastPlaying = false
        guard let url = track.cover else { return }
        if sameArtwork, task != nil || existingArtwork != nil { return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await loadArtwork(url)
                try Task.checkCancellation()
                guard generation == token else { return }
                publishArtwork(image); task = nil
            } catch { if generation == token { task = nil } }
        }
    }
    private func publishArtwork(_ image: NSImage) {
        info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        publish(info, state)
    }
    public func update(elapsed: Double, duration: Double, playing: Bool, force: Bool = false) {
        guard !info.isEmpty else { return }
        // macOS advances its own clock between events; avoid rebuilding metadata every frame.
        guard force || playing != lastPlaying || Date().timeIntervalSince(lastClockUpdate) >= 5 else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, elapsed.isFinite ? elapsed : 0)
        info[MPMediaItemPropertyPlaybackDuration] = max(0, duration.isFinite ? duration : 0)
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        state = playing ? .playing : .paused
        publish(info, state)
        lastClockUpdate = Date(); lastPlaying = playing
    }
    public func clear() {
        task?.cancel(); task = nil; artworkURL = nil; generation = UUID(); info = [:]
        state = .stopped; publish(nil, state)
    }
}
