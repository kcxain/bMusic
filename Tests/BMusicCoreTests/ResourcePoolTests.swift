import Foundation
import Testing
@testable import BMusicCore

private actor ControlledOperation {
    var calls = 0
    var gates: [CheckedContinuation<Void, Never>] = []
    func run() async throws -> Data {
        calls += 1
        await withCheckedContinuation { gates.append($0) }
        try Task.checkCancellation()
        return Data(repeating: 1, count: 4)
    }
    func release() { let pending = gates; gates = []; pending.forEach { $0.resume() } }
    func count() -> Int { calls }
}

struct ResourcePoolTests {
    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<1000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Timed out waiting for controlled operation")
    }
    @Test func sharedRequestSurvivesOneConsumerCancellation() async throws {
        let pool = ResourcePool<String, Data>(concurrency: 1, budget: 8, cost: { $0.count })
        let operation = ControlledOperation()
        let one = Task { try await pool.value(for: "a") { try await operation.run() } }
        try await waitUntil { await operation.count() == 1 }
        let two = Task { try await pool.value(for: "a") { try await operation.run() } }
        // Wait for registration using the actor's consumer count.
        try await waitUntil { await pool.consumerCount(for: "a") == 2 }
        one.cancel()
        await operation.release()
        #expect(try await two.value.count == 4)
        do { _ = try await one.value; Issue.record("Cancelled consumer returned a value") } catch is CancellationError { }
        #expect(await operation.count() == 1)
        let cached = try await pool.value(for: "a") { Issue.record("Cache miss"); return Data() }
        #expect(cached.count == 4)
    }
    @Test func cancelledWorkKeepsSlotUntilItExits() async throws {
        let pool = ResourcePool<String, Data>(concurrency: 1, budget: 8, cost: { $0.count })
        let first = ControlledOperation(), second = ControlledOperation()
        let one = Task { try await pool.value(for: "a") { try await first.run() } }
        try await waitUntil { await first.count() == 1 }
        one.cancel()
        let two = Task { try await pool.value(for: "b") { try await second.run() } }
        try await waitUntil { await pool.statistics().waiting == 1 }
        #expect(await second.count() == 0)
        await first.release()
        try await waitUntil { await second.count() == 1 }
        await second.release()
        _ = try await two.value
        _ = try? await one.value
        #expect(await pool.statistics().active == 0)
    }
    @Test func strictCostBudgetAndExpiry() async throws {
        let pool = ResourcePool<Int, Data>(concurrency: 2, budget: 8, countLimit: 2, lifetime: 0.01, cost: { $0.count })
        await pool.insert(Data(count: 4), for: 1)
        await pool.insert(Data(count: 5), for: 2)
        #expect(await pool.statistics().cachedCost == 5)
        await pool.insert(Data(count: 9), for: 3)
        #expect(await pool.statistics().cachedCost == 5)
        try await Task.sleep(for: .milliseconds(20))
        let value = try await pool.value(for: 2) { Data(count: 2) }
        #expect(value.count == 2)
        #expect(await pool.statistics().cachedCost == 2)
    }
}
