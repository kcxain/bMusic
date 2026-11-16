import Foundation
import Testing
@testable import BMusicCore

struct SearchHistoryTests {
    @Test func historyPersistsAndDeduplicates() throws {
        let suite = "BMusic.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SearchHistory(defaults: defaults)
        store.record("  Jazz  "); store.record("黄霄云"); store.record("jazz"); store.record(" ")
        #expect(SearchHistory(defaults: defaults).entries == ["jazz", "黄霄云"])
        store.remove("jazz")
        #expect(store.entries == ["黄霄云"])
        for index in 0..<30 { store.record("song \(index)") }
        #expect(store.entries.count == 20)
        #expect(store.entries.first == "song 29")
        store.clear()
        #expect(SearchHistory(defaults: defaults).entries.isEmpty)
    }
}
