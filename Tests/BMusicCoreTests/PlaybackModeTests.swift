import Testing
@testable import BMusicCore

struct PlaybackModeTests {
    @Test func cyclesThroughExclusiveModes() {
        var mode = PlaybackMode.sequential
        mode = mode.next
        #expect(mode == .shuffle)
        mode = mode.next
        #expect(mode == .repeatOne)
        mode = mode.next
        #expect(mode == .sequential)
        #expect(Set(PlaybackMode.allCases.map(\.symbol)).count == 3)
    }
}
