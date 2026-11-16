import Foundation

public enum QueueEditing {
    public static func insertionBoundary(row: Int, pointerY: Double, rowHeight: Double) -> Int {
        row + (pointerY >= rowHeight / 2 ? 1 : 0)
    }
    public static func uniqueEntries(from tracks: [Track]) -> [QueueEntry] {
        var seen: Set<String> = []
        return tracks.compactMap { track in
            seen.insert(track.id).inserted ? QueueEntry(track: track) : nil
        }
    }
    @discardableResult
    public static func selectSingle(_ track: Track, in entries: inout [QueueEntry]) -> Int {
        if let index = entries.firstIndex(where: { $0.track.id == track.id }) { return index }
        entries.append(QueueEntry(track: track))
        return entries.count - 1
    }
    /// The destination is an insertion boundary in the original array.
    public static func move(_ entries: inout [QueueEntry], id: UUID, to boundary: Int) {
        guard let source = entries.firstIndex(where: { $0.id == id }) else { return }
        let destination = min(entries.count, max(0, boundary))
        let item = entries.remove(at: source)
        entries.insert(item, at: destination > source ? destination - 1 : destination)
    }
}
