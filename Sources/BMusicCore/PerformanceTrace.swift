import Foundation
import os

/// Fixed-size diagnostics, opt-in console output and Instruments intervals.
public enum PerformanceTrace {
    private static let log = OSLog(subsystem: "io.github.kcxain.BMusic", category: .pointsOfInterest)
    public struct Span: @unchecked Sendable {
        fileprivate let id: OSSignpostID
        fileprivate let started: TimeInterval
        fileprivate let name: String
    }
    public static func begin(_ name: String) -> Span {
        let span = Span(id: OSSignpostID(log: log), started: ProcessInfo.processInfo.systemUptime, name: name)
        os_signpost(.begin, log: log, name: "BMusic operation", signpostID: span.id, "%{public}s", name)
        return span
    }
    public static func end(_ span: Span, outcome: String = "completed") {
        let milliseconds = (ProcessInfo.processInfo.systemUptime - span.started) * 1000
        os_signpost(.end, log: log, name: "BMusic operation", signpostID: span.id, "%{public}s", outcome)
        if ProcessInfo.processInfo.environment["BMUSIC_METRICS"] == "1" {
            print("BMUSIC_METRIC \(span.name) \(String(format: "%.2f", milliseconds))ms \(outcome)")
        }
    }
}
