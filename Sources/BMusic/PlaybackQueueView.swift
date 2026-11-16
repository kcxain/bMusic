import SwiftUI
import UniformTypeIdentifiers
import Observation
import BMusicCore

private extension UTType {
    static let queueEntry = UTType(exportedAs: "io.github.kcxain.BMusic.queue-entry", conformingTo: .data)
}

@MainActor
@Observable
private final class QueueDragState {
    var source: UUID?
    var target: UUID?
    var after = false
    func reset() { source = nil; target = nil; after = false }
}

struct PlaybackQueueView: View {
    @Bindable var player: Player
    @ViewState private var drag = QueueDragState()
    var body: some View {
        MusicPopover(title: "播放队列 · \(player.queue.count)",
                     clear: player.queue.isEmpty ? nil : { player.clearQueue() },
                     clearHelp: "清空队列，保留当前播放") {
            if player.queue.isEmpty {
                Text("选择歌曲后会显示在这里").foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(player.queue) { entry in
                                QueueRow(player: player, entry: entry, drag: drag).id(entry.id)
                            }
                        }
                    }.scrollIndicators(.hidden)
                    .onAppear {
                        if player.queue.indices.contains(player.index) { proxy.scrollTo(player.queue[player.index].id, anchor: .center) }
                    }
                }
            }
        }.onDisappear { drag.reset() }
    }
}

private struct QueueRow: View {
    @Bindable var player: Player
    let entry: QueueEntry
    let drag: QueueDragState
    @ViewState private var hovering = false
    var body: some View {
        HStack(spacing: 4) {
                HStack(spacing: 8) {
                    Artwork(url: entry.track.cover, size: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.track.title).lineLimit(1)
                        Text(entry.track.uploader).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 4)
                }.padding(.vertical, 5).padding(.horizontal, 4).contentShape(Rectangle())
                    .foregroundStyle(player.state(for: entry).isCurrent ? BMusicTheme.pink : .primary)
                .overlay {
                    QueueDragSurface(entry: entry, drag: drag, actionLabel: player.state(for: entry).label) {
                        player.activateEntry(entry.id)
                    }
                }
                .help("点击播放或暂停，拖动调整顺序")
                .frame(minWidth: 0, maxWidth: .infinity)
            Image(systemName: player.state(for: entry).symbol)
                .font(.system(size: 16)).frame(width: 26, height: 32)
                .contentShape(Rectangle())
                .overlay {
                    QueueDragSurface(entry: entry, drag: drag, actionLabel: player.state(for: entry).label) {
                        player.activateEntry(entry.id)
                    }
                }
                .iconHoverFeedback(color: player.state(for: entry).isCurrent ? BMusicTheme.pink : .primary)
                .help(player.state(for: entry).label)
            RemoveItemButton(help: "从播放队列移除", rowHovered: hovering && drag.source == nil) { player.removeEntry(entry.id) }
        }
        .frame(maxWidth: .infinity).frame(height: 44)
        .background(Color.primary.opacity(drag.source == nil && hovering ? 0.06 : (player.state(for: entry).isCurrent ? 0.045 : 0)), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .overlay { QueueInsertionMarker(entryID: entry.id, drag: drag) }
        .onDrop(of: [UTType.queueEntry.identifier], delegate: QueueInsertionDrop(player: player, target: entry.id, drag: drag))
        .contextMenu {
            Button("上移") {
                if let index = player.queue.firstIndex(where: { $0.id == entry.id }) { player.moveEntry(entry.id, to: max(0, index - 1)) }
            }
            Button("下移") {
                if let index = player.queue.firstIndex(where: { $0.id == entry.id }) { player.moveEntry(entry.id, to: index + 2) }
            }
            Button("移除") { player.removeEntry(entry.id) }
        }
    }
}

/// Hover only changes the insertion marker. The queue changes once on release.
private struct QueueInsertionDrop: DropDelegate {
    let player: Player
    let target: UUID
    let drag: QueueDragState
    func validateDrop(info: DropInfo) -> Bool {
        drag.source != nil && info.hasItemsConforming(to: [UTType.queueEntry.identifier])
    }
    func dropEntered(info: DropInfo) { update(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }
    private func update(_ info: DropInfo) {
        let after = QueueEditing.insertionBoundary(row: 0, pointerY: info.location.y, rowHeight: 44) == 1
        if drag.target != target { drag.target = target }
        if drag.after != after { drag.after = after }
    }
    func dropExited(info: DropInfo) {
        if drag.target == target { drag.target = nil }
    }
    func performDrop(info: DropInfo) -> Bool {
        defer { drag.reset() }
        guard let source = drag.source,
              let destination = player.queue.firstIndex(where: { $0.id == target }) else { return false }
        player.moveEntry(source, to: QueueEditing.insertionBoundary(row: destination, pointerY: info.location.y, rowHeight: 44))
        return true
    }
}

private struct QueueInsertionMarker: View {
    let entryID: UUID
    let drag: QueueDragState
    var body: some View {
        VStack(spacing: 0) {
            if drag.after { Spacer(minLength: 0) }
            Rectangle().fill(BMusicTheme.pink).frame(height: 2)
            if !drag.after { Spacer(minLength: 0) }
        }.opacity(drag.target == entryID ? 1 : 0).allowsHitTesting(false)
    }
}

/// One native event path distinguishes an immediate click from a row drag.
private struct QueueDragSurface: NSViewRepresentable {
    let entry: QueueEntry
    let drag: QueueDragState
    let actionLabel: String
    let activate: () -> Void
    func makeNSView(context: Context) -> Surface { Surface(entry: entry, drag: drag, activate: activate) }
    func updateNSView(_ view: Surface, context: Context) {
        view.entry = entry; view.drag = drag; view.activate = activate
        view.setAccessibilityLabel("\(actionLabel) \(entry.track.title)")
    }
    final class Surface: NSView, NSDraggingSource {
        var entry: QueueEntry
        var drag: QueueDragState
        private var start: NSPoint?
        var activate: () -> Void
        init(entry: QueueEntry, drag: QueueDragState, activate: @escaping () -> Void) {
            self.entry = entry; self.drag = drag; self.activate = activate
            super.init(frame: .zero)
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityHelp("点击播放或暂停，拖动调整顺序")
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func accessibilityPerformPress() -> Bool { activate(); return true }
        override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil) }
        override func mouseUp(with event: NSEvent) {
            guard start != nil else { return }
            start = nil
            if bounds.contains(convert(event.locationInWindow, from: nil)) { activate() }
        }
        override func mouseDragged(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            guard let start, hypot(point.x - start.x, point.y - start.y) >= 4 else { return }
            self.start = nil
            drag.reset(); drag.source = entry.id
            let pasteboard = NSPasteboardItem()
            pasteboard.setString(entry.id.uuidString, forType: NSPasteboard.PasteboardType(UTType.queueEntry.identifier))
            let item = NSDraggingItem(pasteboardWriter: pasteboard)
            let title = entry.track.title
            let cover = ArtworkService.shared.loaded.image(for: entry.track.cover) ?? BrandAssets.image
            let preview = NSImage(size: NSSize(width: 220, height: 38), flipped: false) { rect in
                NSColor.windowBackgroundColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
                cover.draw(in: NSRect(x: 5, y: 5, width: 28, height: 28))
                let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
                (title as NSString).draw(in: NSRect(x: 40, y: 10, width: 172, height: 18), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor, .paragraphStyle: style
                ])
                return true
            }
            item.setDraggingFrame(NSRect(x: point.x - 19, y: point.y - 19, width: 220, height: 38), contents: preview)
            beginDraggingSession(with: [item], event: event, source: self).animatesToStartingPositionsOnCancelOrFail = true
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? .move : []
        }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            start = nil; drag.reset()
        }
    }
}
