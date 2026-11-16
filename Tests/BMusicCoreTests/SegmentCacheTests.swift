import Foundation
import Testing
@testable import BMusicCore

struct SegmentCacheTests {
    @Test func reusesOnlyCompleteOriginalSegments() {
        let index = SegmentIndex(initializationLength: 2, segments: [
            .init(offset: 2, length: 3, duration: 1),
            .init(offset: 5, length: 4, duration: 1),
            .init(offset: 9, length: 2, duration: 1)
        ])
        let head = Data(0..<7)
        let cached = index.cachedSegments(in: head)
        #expect(cached.count == 1)
        #expect(cached.first?.0 == 0)
        #expect(cached.first?.1 == Data([2, 3, 4]))
        #expect(index.cachedSegments(in: Data()).isEmpty)
        #expect(index.cachedSegments(in: Data(0..<11)).count == 3)
    }
}
