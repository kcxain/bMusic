import Foundation

public struct SearchHistory {
    private let defaults: UserDefaults
    private let key = "BMusic.searchHistory"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var entries: [String] { defaults.stringArray(forKey: key) ?? [] }
    public func record(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        var values = entries.filter { $0.caseInsensitiveCompare(query) != .orderedSame }
        values.insert(query, at: 0)
        defaults.set(Array(values.prefix(20)), forKey: key)
    }
    public func remove(_ query: String) { defaults.set(entries.filter { $0 != query }, forKey: key) }
    public func clear() { defaults.removeObject(forKey: key) }
}
