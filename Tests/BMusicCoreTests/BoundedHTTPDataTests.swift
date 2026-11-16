import Foundation
import Testing
@testable import BMusicCore

private final class OversizeProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 1, count: 1024))
        client?.urlProtocol(self, didLoad: Data(repeating: 2, count: 1024))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct BoundedHTTPDataTests {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OversizeProtocol.self]
        return URLSession(configuration: config)
    }
    @Test func rejectsChunkedResponseOverBudget() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        await #expect(throws: (any Error).self) {
            try await BoundedHTTPData.load(session: session, request: URLRequest(url: URL(string: "https://fixture.invalid/oversize")!), limit: 1500) { $0.statusCode == 200 }
        }
    }
    @Test func retainsValidResponseAndRejectsUnexpectedStatus() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "https://fixture.invalid/valid")!)
        let data = try await BoundedHTTPData.load(session: session, request: request, limit: 2048) { $0.statusCode == 200 }
        #expect(data.count == 2048)
        await #expect(throws: (any Error).self) {
            try await BoundedHTTPData.load(session: session, request: request, limit: 2048) { $0.statusCode == 206 }
        }
    }
    @Test func cancellationBeforeStartCompletes() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await BoundedHTTPData.load(session: session, request: URLRequest(url: URL(string: "https://fixture.invalid/cancel")!), limit: 2048) { _ in true }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
