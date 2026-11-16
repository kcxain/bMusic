import Foundation

/// One timeline for playback ticks, drag previews, and asynchronous seek completion.
public struct PlaybackPosition: Equatable, Sendable {
    public private(set) var elapsed: Double = 0
    public private(set) var duration: Double = 0
    public private(set) var preview: Double?
    public private(set) var pending: UUID?
    public var displayed: Double { preview ?? elapsed }
    public var isScrubbing: Bool { preview != nil }
    public init() {}
    public mutating func reset(duration: Double) {
        self = PlaybackPosition()
        self.duration = duration.isFinite ? max(0, duration) : 0
    }
    public mutating func tick(_ seconds: Double, duration: Double? = nil) {
        if let duration, duration.isFinite, duration > 0 { self.duration = duration }
        guard pending == nil, preview == nil, seconds.isFinite else { return }
        elapsed = clamp(seconds)
    }
    public mutating func scrub(to seconds: Double) { preview = clamp(seconds) }
    public mutating func cancelScrub() { preview = nil }
    @discardableResult public mutating func seek(to seconds: Double) -> UUID {
        elapsed = clamp(seconds); preview = nil
        let id = UUID(); pending = id
        return id
    }
    @discardableResult public mutating func complete(_ id: UUID, actual: Double) -> Bool {
        guard pending == id else { return false }
        pending = nil
        if actual.isFinite { elapsed = clamp(actual) }
        return true
    }
    private func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, min(value, duration))
    }
}
