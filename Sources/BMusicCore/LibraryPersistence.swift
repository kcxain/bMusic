import Foundation

/// Serial disk access and latest-revision coalescing. The main actor owns optimistic UI state.
public actor LibraryPersistence {
    private let store: LibraryStore
    private var pending: (UInt64, Library)?
    private var committed: UInt64 = 0
    public init(store: LibraryStore = LibraryStore()) { self.store = store }
    public func load() throws -> Library { try store.load() }
    public func stage(_ library: Library, revision: UInt64) {
        guard revision > committed, revision > (pending?.0 ?? 0) else { return }
        pending = (revision, library)
    }
    public func flush() throws {
        guard let (revision, library) = pending else { return }
        try store.save(library)
        committed = revision; pending = nil
    }
}
