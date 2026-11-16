import Foundation
import Testing
@testable import BMusicCore

struct PerformanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BMUSIC_PERF_TESTS"] == "1"))
    func largeLibraryAndWarmCache() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let writer = LibraryPersistence(store: LibraryStore(url: dir.appendingPathComponent("library.json")))
        var library = Library()
        library.favorites = (0..<10000).map { Track(bvid: "BV\($0)", title: "Performance fixture \($0)", uploader: "Artist") }
        var samples: [Double] = []
        for revision in 1...20 {
            let start = ProcessInfo.processInfo.systemUptime
            await writer.stage(library, revision: UInt64(revision))
            try await writer.flush()
            samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        samples.sort()
        print("PERF 10000-track save n=20 p50=\(samples[10])ms p95=\(samples[18])ms")
        #expect(try await writer.load() == library)
        let pool = ResourcePool<Int, Data>(concurrency: 3, budget: 8192, cost: { $0.count })
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<1000 { _ = try await pool.value(for: 1) { Data(count: 4096) } }
        print("PERF 1000 warm lookups=\((ProcessInfo.processInfo.systemUptime - start) * 1000)ms cache=\(await pool.statistics().cachedCost) bytes")
    }
}
