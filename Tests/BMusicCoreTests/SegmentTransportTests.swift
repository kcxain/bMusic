import Foundation
import Testing
@testable import BMusicCore

private final class AudioFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var counts: [String: Int] = [:]
    static func count(_ range: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[range, default: 0] }
    static func integer(_ value: UInt64) -> Data {
        Data((0..<4).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    static let head: Data = {
        var body = Data([0, 0, 0, 0])
        body += integer(1); body += integer(48000)
        body += integer(0); body += integer(300000)
        body += Data([0, 0, 0, 1])
        body += integer(100); body += integer(240000); body += integer(0x90000000)
        return integer(8) + Data("ftyp".utf8) + integer(UInt64(body.count + 8)) + Data("sidx".utf8) + body
    }()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let range = request.value(forHTTPHeaderField: "Range") ?? ""
        Self.lock.lock(); Self.counts[range, default: 0] += 1; Self.lock.unlock()
        let data = range.hasPrefix("bytes=0-") ? Self.head : Data(repeating: 0xAB, count: 100)
        let start = range.dropFirst(6).split(separator: "-").first.flatMap { Int($0) } ?? 0
        let response = HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: nil,
                                       headerFields: ["Content-Range": "bytes \(start)-\(start + data.count - 1)/999999"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct SegmentTransportTests {
    @Test func servesPlaylistAndOriginalSegmentsThroughLoopback() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AudioFixtureProtocol.self]
        let session = URLSession(configuration: config)
        let source = try await IndexedAudioAsset.prepare(url: URL(string: "https://fixture.invalid/\(UUID())")!, session: session)
        let (playlist, _) = try await URLSession.shared.data(from: source.asset.url)
        #expect(String(decoding: playlist, as: UTF8.self).contains("segment/0.m4s"))
        let segmentURL = source.asset.url.deletingLastPathComponent().appendingPathComponent("segment/0.m4s")
        async let first = URLSession.shared.data(from: segmentURL)
        async let second = URLSession.shared.data(from: segmentURL)
        let (one, two) = try await (first, second)
        #expect(one.0 == Data(repeating: 0xAB, count: 100))
        #expect(one.0 == two.0)
        let offset = AudioFixtureProtocol.head.count + 300000
        #expect(AudioFixtureProtocol.count("bytes=\(offset)-\(offset + 99)") == 1)
        withExtendedLifetime(source) {}
    }
}
