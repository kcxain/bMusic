import Foundation
import Testing
@testable import BMusicCore

struct SegmentIndexTests {
    private func integer(_ value: UInt64, width: Int = 4) -> [UInt8] {
        (0..<width).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }
    private func fixture(version: UInt8 = 0, nested: Bool = false) -> Data {
        let width = version == 0 ? 4 : 8
        var body: [UInt8] = [version, 0, 0, 0]
        body += integer(1) + integer(48000)
        body += integer(0, width: width) + integer(16, width: width)
        body += [0, 0, 0, 2]
        body += integer(nested ? 0x80000064 : 100) + integer(240000) + integer(0x90000000)
        body += integer(200) + integer(144000) + integer(0x90000000)
        return Data(integer(8) + Array("ftyp".utf8) + integer(UInt64(body.count + 8)) + Array("sidx".utf8) + body)
    }
    @Test func versionsAndOffsets() throws {
        for version: UInt8 in [0, 1] {
            let bytes = fixture(version: version)
            let index = try SegmentIndex.parse(bytes)
            #expect(index.initializationLength == 8)
            #expect(index.segments.count == 2)
            #expect(index.segments[0].offset == UInt64(bytes.count + 16))
            #expect(index.segments[1].offset == UInt64(bytes.count + 116))
            #expect(index.segments[0].duration == 5)
            #expect(index.segments[1].duration == 3)
            #expect(index.playlist.contains("#EXT-X-TARGETDURATION:5"))
            #expect(index.playlist.contains("#EXT-X-MAP:URI=\"init.mp4\""))
            #expect(index.playlist.contains("#EXTINF:3.000000,\nsegment/1.m4s"))
            #expect(index.playlist.hasSuffix("#EXT-X-ENDLIST\n"))
        }
    }
    @Test func malformedAndNestedReferences() {
        #expect(throws: (any Error).self) { try SegmentIndex.parse(fixture().dropLast()) }
        #expect(throws: (any Error).self) { try SegmentIndex.parse(fixture(nested: true)) }
        #expect(throws: (any Error).self) { try SegmentIndex.parse(Data([0,0,0,0,115,105,100,120])) }
    }
}
