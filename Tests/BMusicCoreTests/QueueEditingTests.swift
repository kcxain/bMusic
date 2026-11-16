import Foundation
import Testing
@testable import BMusicCore

struct QueueEditingTests {
    @Test func insertionLineMatchesCommittedBoundary() {
        #expect(QueueEditing.insertionBoundary(row: 3, pointerY: 0, rowHeight: 44) == 3)
        #expect(QueueEditing.insertionBoundary(row: 3, pointerY: 21, rowHeight: 44) == 3)
        #expect(QueueEditing.insertionBoundary(row: 3, pointerY: 22, rowHeight: 44) == 4)
        #expect(QueueEditing.insertionBoundary(row: 3, pointerY: 44, rowHeight: 44) == 4)
    }
    @Test func deduplicatesAcrossSourcesAndPreservesPartsAndOrder() {
        let first = Track(bvid: "BVsame", cid: 123, title: "Resolved", uploader: "")
        let searchCopy = Track(bvid: "BVsame", title: "Search title", uploader: "")
        let secondPart = Track(bvid: "BVsame", cid: 456, title: "Part 2", uploader: "", part: 2)
        var queue = QueueEditing.uniqueEntries(from: [first, searchCopy, secondPart, first])
        #expect(queue.map(\.track) == [first, secondPart])
        let ids = queue.map(\.id)
        for _ in 0..<10 { QueueEditing.selectSingle(searchCopy, in: &queue) }
        #expect(queue.map(\.id) == ids)
        #expect(queue[0].track.cid == 123)
        QueueEditing.move(&queue, id: ids[0], to: 2)
        #expect(QueueEditing.selectSingle(searchCopy, in: &queue) == 1)
        #expect(queue.map(\.id) == [ids[1], ids[0]])
    }
    @Test func searchSelectionAppendsOnlyChosenTrackAndReusesExistingEntry() {
        let original = Track(bvid: "BVoriginal", title: "Original", uploader: "")
        let chosen = Track(bvid: "BVchosen", title: "Chosen", uploader: "")
        var queue = [QueueEntry(track: original)]
        let originalID = queue[0].id
        #expect(QueueEditing.selectSingle(chosen, in: &queue) == 1)
        #expect(queue.map(\.track) == [original, chosen])
        let chosenID = queue[1].id
        #expect(QueueEditing.selectSingle(chosen, in: &queue) == 1)
        #expect(queue.map(\.id) == [originalID, chosenID])
    }
    @Test func movesDuplicateTracksByEntryIdentity() {
        let song = Track(bvid: "BVsame", title: "Same", uploader: "")
        let entries = (0..<4).map { _ in QueueEntry(track: song) }
        var queue = entries
        QueueEditing.move(&queue, id: entries[0].id, to: 4)
        #expect(queue.map(\.id) == [entries[1].id, entries[2].id, entries[3].id, entries[0].id])
        QueueEditing.move(&queue, id: entries[0].id, to: 0)
        #expect(queue.map(\.id) == entries.map(\.id))
        QueueEditing.move(&queue, id: entries[1].id, to: 2)
        #expect(queue.map(\.id) == entries.map(\.id))
        QueueEditing.move(&queue, id: UUID(), to: 0)
        #expect(queue.count == 4)
        QueueEditing.move(&queue, id: entries[3].id, to: -100)
        #expect(queue.first?.id == entries[3].id)
    }
}
