import AVFoundation
import Foundation
import Network

/// Presents the original fMP4 audio fragments as HLS using their existing sidx index.
/// A loopback-only endpoint supplies bounded fragments without scanning a multi-hour file.
public final class IndexedAudioAsset {
    private static let heads = ResourcePool<URL, Data>(concurrency: 2, budget: 512 * 1024, countLimit: 2,
                                                      lifetime: 45, cost: { $0.count })
    private static let headSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.timeoutIntervalForRequest = 8; config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()
    public static func prefetchHead(url: URL) async throws {
        _ = try await heads.value(for: url, priority: -10) {
            try await fetch(session: headSession, url: url, offset: 0, length: 262144)
        }
    }
    public let asset: AVURLAsset
    public let segmentCount: Int
    private let server: AudioSegmentServer
    private init(server: AudioSegmentServer, url: URL, segmentCount: Int) {
        self.server = server; self.asset = AVURLAsset(url: url); self.segmentCount = segmentCount
    }
    public static func prepare(url: URL, session suppliedSession: URLSession? = nil) async throws -> IndexedAudioAsset {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 12
        configuration.httpMaximumConnectionsPerHost = 4
        let session = suppliedSession ?? URLSession(configuration: configuration)
        let headerSession = suppliedSession ?? headSession
        do {
            let head = try await heads.value(for: url, priority: 10) {
                try await fetch(session: headerSession, url: url, offset: 0, length: 262144)
            }
            let index = try SegmentIndex.parse(head)
            guard index.initializationLength > 0 else { throw BMusicError.invalidResponse }
            let server = try AudioSegmentServer(remote: url, session: session, index: index, head: head)
            let localURL = try await server.start()
            return IndexedAudioAsset(server: server, url: localURL, segmentCount: index.segments.count)
        } catch { session.invalidateAndCancel(); throw error }
    }
    fileprivate static func fetch(session: URLSession, url: URL, offset: UInt64, length: UInt64) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(offset)-\(offset + length - 1)", forHTTPHeaderField: "Range")
        request.setValue(BilibiliClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        guard length > 0, length <= 16 * 1024 * 1024 else { throw BMusicError.invalidResponse }
        return try await BoundedHTTPData.load(session: session, request: request, limit: Int(length)) { response in
            response.statusCode == 206 && response.value(forHTTPHeaderField: "Content-Range")?.hasPrefix("bytes \(offset)-") == true
        }
    }
    deinit { server.stop() }
}

private final class AudioSegmentServer: @unchecked Sendable {
    private let remote: URL
    private let session: URLSession
    private let index: SegmentIndex
    private let initialization: Data
    private let playlist: Data
    private let listener: NWListener
    private let queue = DispatchQueue(label: "BMusic.audio-segments", qos: .userInitiated)
    private let token = UUID().uuidString
    private var startResolved = false
    private var connections: [UUID: NWConnection] = [:]
    private let segments = ResourcePool<Int, Data>(concurrency: 2, budget: 4 * 1024 * 1024, countLimit: 32, cost: { $0.count })
    private let seed: [(Int, Data)]
    private var transfers: [UUID: Task<Void, Never>] = [:]
    init(remote: URL, session: URLSession, index: SegmentIndex, head: Data) throws {
        self.remote = remote; self.session = session; self.index = index
        self.initialization = head.prefix(index.initializationLength)
        self.playlist = Data(index.playlist.utf8)
        seed = index.cachedSegments(in: head)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }
    func start() async throws -> URL {
        for (number, bytes) in seed { await segments.insert(bytes, for: number) }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, !self.startResolved else { return }
                switch state {
                case .ready:
                    self.startResolved = true
                    guard let port = self.listener.port else { continuation.resume(throwing: BMusicError.invalidResponse); return }
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)/\(self.token)/index.m3u8")!)
                case .failed(let error): self.startResolved = true; continuation.resume(throwing: error)
                case .cancelled: self.startResolved = true; continuation.resume(throwing: CancellationError())
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
        }
    }
    func stop() {
        listener.cancel(); session.invalidateAndCancel()
        queue.async { [self] in
            transfers.values.forEach { $0.cancel() }; transfers.removeAll()
            connections.values.forEach { $0.cancel() }; connections.removeAll()
        }
    }
    private func accept(_ connection: NWConnection) {
        guard connections.count < 12 else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { self?.transfers.removeValue(forKey: id)?.cancel(); self?.connections.removeValue(forKey: id) }
        }
        connection.start(queue: queue)
        receive(connection, id: id, data: Data())
    }
    private func receive(_ connection: NWConnection, id: UUID, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] bytes, _, complete, error in
            guard let self else { connection.cancel(); return }
            var accumulated = data; if let bytes { accumulated.append(bytes) }
            if accumulated.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(connection, id: id, request: accumulated)
            } else if complete || error != nil || accumulated.count > 16384 { connection.cancel() }
            else { self.receive(connection, id: id, data: accumulated) }
        }
    }
    private func respond(_ connection: NWConnection, id: UUID, request: Data) {
        guard let line = String(data: request, encoding: .utf8)?.components(separatedBy: "\r\n").first else { connection.cancel(); return }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET", parts[1].hasPrefix("/\(token)/") else {
            send(connection, data: Data(), type: "text/plain", status: "404 Not Found"); return
        }
        let path = String(parts[1].dropFirst(token.count + 2))
        if path == "index.m3u8" { send(connection, data: playlist, type: "application/vnd.apple.mpegurl"); return }
        if path == "init.mp4" { send(connection, data: initialization, type: "audio/mp4"); return }
        guard path.hasPrefix("segment/"), path.hasSuffix(".m4s"),
              let number = Int(path.dropFirst(8).dropLast(4)), index.segments.indices.contains(number) else {
            send(connection, data: Data(), type: "text/plain", status: "404 Not Found"); return
        }
        let segment = index.segments[number]
        transfers[id] = Task { [weak self] in
            guard let self else { return }
            do {
                let session = session, remote = remote
                let data = try await segments.value(for: number) {
                    try await IndexedAudioAsset.fetch(session: session, url: remote, offset: segment.offset, length: UInt64(segment.length))
                }
                try Task.checkCancellation()
                queue.async { [self] in
                    self.send(connection, data: data, type: "audio/mp4")
                    self.transfers.removeValue(forKey: id)
                }
            } catch {
                queue.async { [self] in self.send(connection, data: Data(), type: "text/plain", status: "502 Bad Gateway"); self.transfers.removeValue(forKey: id) }
            }
        }
    }
    private func send(_ connection: NWConnection, data: Data, type: String, status: String = "200 OK") {
        var response = Data("HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(data.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n".utf8)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}
