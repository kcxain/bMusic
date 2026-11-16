import Foundation

public struct QueueEntry: Identifiable, Sendable {
    public let id: UUID
    public var track: Track
    public init(track: Track) { id = UUID(); self.track = track }
}
