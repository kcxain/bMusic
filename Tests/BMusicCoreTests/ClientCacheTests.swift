import Foundation
import Testing
@testable import BMusicCore

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var counts: [String: Int] = [:]
    static func count(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[path, default: 0] }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!, path = url.path
        Self.lock.lock(); Self.counts[path, default: 0] += 1; Self.lock.unlock()
        let data: String
        switch path {
        case "/x/web-interface/nav":
            data = #"{"code":0,"data":{"isLogin":false,"wbi_img":{"img_url":"https://example.com/7cd084941338484aae1ad9425b84077c.png","sub_url":"https://example.com/4932caff0ff746eab6f01bf08b70ac45.png"}}}"#
        case "/x/web-interface/wbi/search/type":
            data = #"{"code":0,"data":{"numPages":3,"result":[{"bvid":"BVfixture","title":"Fixture","author":"Artist","duration":"3:20"}]}}"#
        default: data = "{}"
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(data.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct ClientCacheTests {
    @Test func repeatedSearchUsesCacheAndPageScopeAreIndependent() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = BilibiliClient(session: session)
        let path = "/x/web-interface/wbi/search/type"
        let before = FixtureProtocol.count(path)
        let first = try await client.search("cache fixture")
        let again = try await client.search("cache fixture")
        #expect(first.tracks == again.tracks)
        #expect(FixtureProtocol.count(path) - before == 1)
        _ = try await client.search("cache fixture", page: 2)
        _ = try await client.search("cache fixture", musicOnly: false)
        #expect(FixtureProtocol.count(path) - before == 3)
    }
}
