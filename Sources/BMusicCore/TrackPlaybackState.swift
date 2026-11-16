import Foundation

/// Every surface derives its action and icon from the same current-track identity.
public enum TrackPlaybackState: Equatable, Sendable {
    case idle, playing, paused, failed
    public init(trackID: String, currentID: String?, intendsPlayback: Bool, failed: Bool) {
        guard trackID == currentID else { self = .idle; return }
        self = failed ? .failed : (intendsPlayback ? .playing : .paused)
    }
    public var isCurrent: Bool { self != .idle }
    public var symbol: String { self == .playing ? "pause.fill" : "play.fill" }
    public var label: String { self == .playing ? "暂停" : (self == .paused ? "继续播放" : (self == .failed ? "重试播放" : "播放")) }
    public var shouldToggle: Bool { self == .playing || self == .paused }
}
