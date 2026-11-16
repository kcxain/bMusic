import Foundation

/// One small public chart snapshot; stale data provides an immediate first frame.
public actor DiscoveryCache {
    private struct Snapshot: Codable { let date: Date; let tracks: [Track] }
    private let url: URL
    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BMusic/discovery.json")
    }
    public func load() -> [Track]? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 256 * 1024,
              let data = try? Data(contentsOf: url), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              Date().timeIntervalSince(snapshot.date) < 7 * 86400 else { return nil }
        return Array(snapshot.tracks.prefix(12))
    }
    public func save(_ tracks: [Track]) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Snapshot(date: Date(), tracks: Array(tracks.prefix(12))))
            guard data.count <= 256 * 1024 else { return }
            try data.write(to: url, options: .atomic)
        } catch { /* A chart cache failure does not affect the library. */ }
    }
}
