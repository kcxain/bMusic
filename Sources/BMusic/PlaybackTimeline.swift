import AVFoundation
import BMusicCore

/// High-frequency UI state stays separate from queue and track metadata.
@MainActor
final class PlaybackTimeline: ObservableObject {
    @Published private(set) var position = PlaybackPosition()
    @Published private(set) var buffered: [ClosedRange<Double>] = []
    private var lastBufferSample = -Double.infinity
    var elapsed: Double { position.displayed }
    var duration: Double { position.duration }
    var isSeeking: Bool { position.pending != nil }
    var isScrubbing: Bool { position.isScrubbing }
    func reset(duration: Double) { position.reset(duration: duration); buffered = []; lastBufferSample = -.infinity }
    func tick(_ seconds: Double, item: AVPlayerItem?) {
        var next = position
        next.tick(seconds, duration: item?.duration.seconds)
        if next != position { position = next }
        // Buffer decoration needs fewer reads than the continuous playhead.
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastBufferSample >= 0.5 else { return }
        lastBufferSample = now
        let ranges = (item?.loadedTimeRanges ?? []).compactMap { value -> ClosedRange<Double>? in
            let range = value.timeRangeValue
            let start = range.start.seconds, end = CMTimeRangeGetEnd(range).seconds
            guard start.isFinite, end.isFinite, end >= start else { return nil }
            return start...end
        }
        if ranges != buffered { buffered = ranges }
    }
    func scrub(to seconds: Double) { position.scrub(to: seconds) }
    func cancelScrub() { position.cancelScrub() }
    func seek(to seconds: Double) -> UUID { position.seek(to: seconds) }
    @discardableResult func complete(_ id: UUID, actual: Double) -> Bool { position.complete(id, actual: actual) }
}
