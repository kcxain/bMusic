import Foundation

/// Shared work with consumer cancellation, bounded concurrency and a strict LRU budget.
public actor ResourcePool<Key: Hashable & Sendable, Value: Sendable> {
    public struct Statistics: Sendable {
        public let active: Int
        public let waiting: Int
        public let cachedCost: Int
        public let cachedCount: Int
    }
    private struct Entry {
        let value: Value
        let cost: Int
        let expiry: Date
        var access: UInt64
    }
    private struct Work {
        let token: UUID
        var consumers: [UUID: CheckedContinuation<Value, Error>]
        let operation: @Sendable () async throws -> Value
        var priority: Int
        let order: UInt64
        var task: Task<Void, Never>?
    }
    private let concurrency: Int
    private let budget: Int
    private let countLimit: Int
    private let lifetime: TimeInterval
    private let cost: @Sendable (Value) -> Int
    private var entries: [Key: Entry] = [:]
    private var work: [Key: Work] = [:]
    private var running: Set<UUID> = []
    private var clock: UInt64 = 0
    private var cachedCost = 0

    public init(concurrency: Int, budget: Int, countLimit: Int = 128, lifetime: TimeInterval = 900,
                cost: @escaping @Sendable (Value) -> Int) {
        self.concurrency = max(1, concurrency); self.budget = max(0, budget)
        self.countLimit = max(0, countLimit); self.lifetime = lifetime; self.cost = cost
    }
    public func value(for key: Key, priority: Int = 0,
                      operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        clock &+= 1
        if var entry = entries[key] {
            if entry.expiry > Date() {
                entry.access = clock; entries[key] = entry
                return entry.value
            }
            remove(key)
        }
        let consumer = UUID()
        let result: Value = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if var existing = work[key] {
                    existing.consumers[consumer] = continuation
                    existing.priority = max(existing.priority, priority); work[key] = existing
                } else {
                    work[key] = Work(token: UUID(), consumers: [consumer: continuation], operation: operation,
                                     priority: priority, order: clock)
                }
                schedule()
            }
        } onCancel: {
            Task { await self.cancel(key, consumer: consumer) }
        }
        try Task.checkCancellation()
        return result
    }
    public func insert(_ value: Value, for key: Key) {
        let bytes = max(0, cost(value))
        remove(key)
        guard bytes <= budget, countLimit > 0, budget > 0 else { return }
        while cachedCost + bytes > budget || entries.count >= countLimit {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key else { break }
            remove(oldest)
        }
        clock &+= 1
        entries[key] = Entry(value: value, cost: bytes, expiry: Date().addingTimeInterval(lifetime), access: clock)
        cachedCost += bytes
    }
    func consumerCount(for key: Key) -> Int { work[key]?.consumers.count ?? 0 }
    public func clear() { entries.removeAll(); cachedCost = 0 }
    public func statistics() -> Statistics {
        Statistics(active: running.count, waiting: work.values.filter { $0.task == nil }.count,
                   cachedCost: cachedCost, cachedCount: entries.count)
    }
    private func remove(_ key: Key) {
        if let removed = entries.removeValue(forKey: key) { cachedCost -= removed.cost }
    }
    private func cancel(_ key: Key, consumer: UUID) {
        guard var pending = work[key], let continuation = pending.consumers.removeValue(forKey: consumer) else { return }
        continuation.resume(throwing: CancellationError())
        if pending.consumers.isEmpty {
            pending.task?.cancel(); work[key] = nil
            // Keep the running slot until the operation actually exits.
        } else { work[key] = pending }
        schedule()
    }
    private func schedule() {
        while running.count < concurrency {
            guard let next = work.filter({ $0.value.task == nil }).max(by: {
                $0.value.priority == $1.value.priority ? $0.value.order > $1.value.order : $0.value.priority < $1.value.priority
            }) else { return }
            let key = next.key, operation = next.value.operation, token = next.value.token
            running.insert(token)
            work[key]?.task = Task {
                let result: Result<Value, Error>
                do { result = .success(try await operation()) }
                catch { result = .failure(error) }
                self.finish(key, token: token, result: result)
            }
        }
    }
    private func finish(_ key: Key, token: UUID, result: Result<Value, Error>) {
        running.remove(token)
        if let pending = work[key], pending.token == token {
            work[key] = nil
            if case let .success(value) = result { insert(value, for: key) }
            for continuation in pending.consumers.values { continuation.resume(with: result) }
        }
        schedule()
    }
}
