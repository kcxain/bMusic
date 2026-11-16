import Foundation
import CFNetwork
import Darwin

/// Routes only BMusic update traffic. Forwarded chunks stay in Sparkle's downloader.
final class UpdateProxyProtocol: URLProtocol, URLSessionDataDelegate, @unchecked Sendable {
    private var session: URLSession?
    private var transfer: URLSessionDataTask?
    private static let handled = "BMusicUpdateProxyHandled"
    override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: handled, in: request) == nil,
              let url = request.url, url.scheme == "https" else { return false }
        return url.host == "github.com" && url.path.hasPrefix("/kcxain/bMusic/releases/")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = []
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: "updateProxyMode") ?? "auto"
        let savedPort = defaults.integer(forKey: "updateProxyPort")
        let port = (1...65535).contains(savedPort) ? savedPort : 7890
        if mode == "manual" || (mode == "auto" && !Self.hasSystemProxy && Self.portIsOpen(port)) {
            config.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": port,
                                               "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": port]
        } else if mode == "direct" { config.connectionProxyDictionary = [:] }
        let request = (self.request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: Self.handled, in: request)
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        transfer = session.dataTask(with: request as URLRequest)
        transfer?.resume()
    }
    override func stopLoading() {
        transfer?.cancel(); transfer = nil
        session?.invalidateAndCancel(); session = nil
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        client?.urlProtocol(self, didLoad: data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { client?.urlProtocol(self, didFailWithError: error) }
        else { client?.urlProtocolDidFinishLoading(self) }
        session.finishTasksAndInvalidate(); self.session = nil; transfer = nil
    }
    private static var hasSystemProxy: Bool {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else { return false }
        return ["HTTPEnable", "HTTPSEnable", "SOCKSEnable", "ProxyAutoConfigEnable", "ProxyAutoDiscoveryEnable"]
            .contains { (settings[$0] as? NSNumber)?.boolValue == true }
    }
    private static func portIsOpen(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }; defer { close(fd) }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian; address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if result == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&descriptor, 1, 100) > 0 else { return false }
        var error: Int32 = 0; var length = socklen_t(MemoryLayout<Int32>.size)
        return getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 && error == 0
    }
}
