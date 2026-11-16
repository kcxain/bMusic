import Foundation

/// The AppKit source and SwiftUI destination share one explicit wire format.
public struct TrackDragPayload: Codable, Sendable {
    public let track: Track
    public init(track: Track) { self.track = track }
    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> Track {
        guard data.count <= 256 * 1024 else { throw BMusicError.invalidResponse }
        let track = try JSONDecoder().decode(Self.self, from: data).track
        guard !track.bvid.isEmpty, track.part > 0 else { throw BMusicError.invalidResponse }
        return track
    }
}
