import Foundation

/// Only durable identifiers and playback preferences are persisted, never CDN URLs.
public struct PlaybackSession: Codable, Sendable, Equatable {
    public var version = 1
    public var tracks: [Track]
    public var currentTrackID: String?
    public var currentTrack: Track?
    public var elapsed: Double
    public var mode: PlaybackMode
    public var volume: Double
    public var qualityID: Int?

    public init(tracks: [Track], currentTrackID: String?, elapsed: Double,
                mode: PlaybackMode, volume: Double, qualityID: Int? = nil, currentTrack: Track? = nil) {
        self.tracks = tracks; self.currentTrackID = currentTrackID; self.elapsed = elapsed
        self.currentTrack = currentTrack
        self.mode = mode; self.volume = volume; self.qualityID = qualityID
    }
    public func validated() throws -> Self {
        guard version == 1 else { throw BMusicError.storage("播放记录版本暂不支持") }
        var result = self
        var seen: Set<String> = []
        result.tracks = tracks.filter { !$0.bvid.isEmpty && $0.part > 0 && seen.insert($0.id).inserted }
        result.volume = volume.isFinite ? min(1, max(0, volume)) : 0.8
        if let track = result.currentTrack,
           track.bvid.isEmpty || track.part < 1 || track.id != currentTrackID { result.currentTrack = nil }
        if let current = result.currentTrack ?? result.tracks.first(where: { $0.id == currentTrackID }) {
            result.elapsed = elapsed.isFinite ? max(0, elapsed) : 0
            if current.duration.isFinite, current.duration > 0 { result.elapsed = min(result.elapsed, current.duration) }
        } else { result.currentTrackID = nil; result.elapsed = 0 }
        return result
    }
}

public actor PlaybackSessionStore {
    public let url: URL
    private var revision: UInt64 = 0
    private var lastSaved: PlaybackSession?
    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BMusic/playback.json")
    }
    public func load() throws -> PlaybackSession? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let result = try JSONDecoder().decode(PlaybackSession.self, from: Data(contentsOf: url)).validated()
        lastSaved = result
        return result
    }
    public func save(_ snapshot: PlaybackSession, revision: UInt64) throws {
        guard revision > self.revision else { return }
        let valid = try snapshot.validated()
        if valid != lastSaved {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(valid).write(to: url, options: .atomic)
            lastSaved = valid
        }
        self.revision = revision
    }
}
