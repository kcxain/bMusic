import Foundation

/// ISO/IEC 14496-12 sidx, preserving source bytes and timestamps.
public struct SegmentIndex: Sendable {
    public struct Segment: Sendable {
        public let offset: UInt64
        public let length: UInt32
        public let duration: Double
    }
    public let initializationLength: Int
    public let segments: [Segment]
    func cachedSegments(in head: Data) -> [(Int, Data)] {
        segments.enumerated().compactMap { number, segment in
            guard segment.offset <= UInt64(head.count),
                  UInt64(segment.length) <= UInt64(head.count) - segment.offset else { return nil }
            let start = Int(segment.offset)
            return (number, head.subdata(in: start..<start + Int(segment.length)))
        }
    }
    public static func parse(_ data: Data) throws -> SegmentIndex {
        let bytes = [UInt8](data)
        func number(_ offset: Int, _ length: Int) throws -> UInt64 {
            guard offset >= 0, offset + length <= bytes.count else { throw BMusicError.invalidResponse }
            return bytes[offset..<offset + length].reduce(0) { ($0 << 8) | UInt64($1) }
        }
        var box = 0
        while box + 8 <= bytes.count {
            var size = try number(box, 4)
            let kind = String(bytes: bytes[box + 4..<box + 8], encoding: .ascii)
            var header = 8
            if size == 1 { size = try number(box + 8, 8); header = 16 }
            guard size >= UInt64(header), size <= UInt64(Int.max - box) else { throw BMusicError.invalidResponse }
            if kind == "sidx" {
                guard box + Int(size) <= bytes.count else { throw BMusicError.invalidResponse }
                let body = box + header
                let version = try number(body, 1)
                guard version <= 1 else { throw BMusicError.invalidResponse }
                let timescale = try number(body + 8, 4)
                guard timescale > 0 else { throw BMusicError.invalidResponse }
                let width = version == 0 ? 4 : 8
                let firstOffset = try number(body + 12 + width, width)
                let countPosition = body + 12 + width * 2 + 2
                let count = try number(countPosition, 2)
                var cursor = countPosition + 2
                var offset = UInt64(box) + size + firstOffset
                var segments: [Segment] = []
                for _ in 0..<count {
                    guard cursor + 12 <= box + Int(size) else { throw BMusicError.invalidResponse }
                    let reference = try number(cursor, 4)
                    guard reference & 0x80000000 == 0 else { throw BMusicError.invalidResponse }
                    let length = UInt32(reference & 0x7fffffff)
                    let duration = Double(try number(cursor + 4, 4)) / Double(timescale)
                    guard length > 0, duration > 0, offset <= UInt64.max - UInt64(length) else { throw BMusicError.invalidResponse }
                    segments.append(Segment(offset: offset, length: length, duration: duration))
                    offset += UInt64(length); cursor += 12
                }
                guard !segments.isEmpty else { throw BMusicError.invalidResponse }
                return SegmentIndex(initializationLength: box, segments: segments)
            }
            box += Int(size)
        }
        throw BMusicError.invalidResponse
    }
    public var playlist: String {
        let target = Int(ceil(segments.map(\.duration).max() ?? 1))
        var lines = ["#EXTM3U", "#EXT-X-VERSION:7", "#EXT-X-TARGETDURATION:\(target)", "#EXT-X-MEDIA-SEQUENCE:0", "#EXT-X-PLAYLIST-TYPE:VOD", "#EXT-X-MAP:URI=\"init.mp4\""]
        for (i, segment) in segments.enumerated() {
            lines += [String(format: "#EXTINF:%.6f,", locale: Locale(identifier: "en_US_POSIX"), segment.duration), "segment/\(i).m4s"]
        }
        return (lines + ["#EXT-X-ENDLIST", ""]).joined(separator: "\n")
    }
}
