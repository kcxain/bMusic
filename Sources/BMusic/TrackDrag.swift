import SwiftUI
import UniformTypeIdentifiers
import BMusicCore

extension UTType {
    static let bmusicTrack = UTType(exportedAs: "io.github.kcxain.BMusic.track", conformingTo: .data)
}

private extension Notification.Name {
    static let trackDragEnded = Notification.Name("BMusic.trackDragEnded")
}

extension View {
    func draggableTrack(_ track: Track) -> some View {
        background(TrackDragSource(track: track))
    }
}

/// AppKit supplies an explicit drag-image frame in source-view coordinates.
/// The cover's centre stays under the pointer regardless of where a row was grabbed.
private struct TrackDragSource: NSViewRepresentable {
    let track: Track
    func makeNSView(context: Context) -> TrackDragView { TrackDragView(track: track) }
    func updateNSView(_ view: TrackDragView, context: Context) { view.track = track }
    static func dismantleNSView(_ view: TrackDragView, coordinator: ()) { view.stopMonitoring() }
}

private final class TrackDragView: NSView, NSDraggingSource {
    var track: Track
    private static let sources = NSHashTable<TrackDragView>.weakObjects()
    private static var monitor: Any?
    private static weak var active: TrackDragView?
    private static var mouseDown: NSEvent?
    private var pressed: NSPoint?
    private var pressedTrack: Track?
    init(track: Track) { self.track = track; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        Self.sources.add(self)
        guard Self.monitor == nil else { return }
        Self.monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { event in
            if event.type == .leftMouseDown {
                Self.mouseDown = event
                // Resolve once at mouse-down; lazy carousel cells may move or be
                // reused before the first drag event arrives.
                Self.active = Self.sources.allObjects.filter { $0.containsVisiblePoint(event) }
                    .min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
                _ = Self.active?.handle(event)
                return event
            }
            let result: NSEvent?
            if let active = Self.active { result = active.handle(event) }
            else { result = event }
            if event.type == .leftMouseUp { Self.active = nil; Self.mouseDown = nil }
            return result
        }
    }
    func stopMonitoring() {
        Self.sources.remove(self)
        if Self.active === self { Self.active = nil }
        if Self.sources.allObjects.isEmpty, let monitor = Self.monitor {
            NSEvent.removeMonitor(monitor); Self.monitor = nil
        }
        pressed = nil; pressedTrack = nil
    }
    private func containsVisiblePoint(_ event: NSEvent) -> Bool {
        guard window === event.window, !isHiddenOrHasHiddenAncestor,
              bounds.contains(convert(event.locationInWindow, from: nil)),
              visibleRect.contains(convert(event.locationInWindow, from: nil)) else { return false }
        var ancestor = superview
        while let view = ancestor {
            if view is NSClipView, !view.bounds.contains(view.convert(event.locationInWindow, from: nil)) { return false }
            ancestor = view.superview
        }
        return true
    }
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === window, !isHiddenOrHasHiddenAncestor else { pressed = nil; return event }
        let location = convert(event.locationInWindow, from: nil)
        switch event.type {
        case .leftMouseDown:
            pressed = containsVisiblePoint(event) ? location : nil
            pressedTrack = pressed == nil ? nil : track
        case .leftMouseUp:
            pressed = nil; pressedTrack = nil
        case .leftMouseDragged:
            guard let track = pressedTrack, let start = pressed, hypot(location.x - start.x, location.y - start.y) >= 6 else { return event }
            pressed = nil
            guard let data = try? TrackDragPayload(track: track).encoded() else { return event }
            let pasteboard = NSPasteboardItem()
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(UTType.bmusicTrack.identifier))
            let item = NSDraggingItem(pasteboardWriter: pasteboard)
            let size = NSSize(width: 240, height: 44)
            let cover = ArtworkService.shared.loaded.image(for: track.cover) ?? BrandAssets.image
            let image = NSImage(size: size, flipped: false) { [track, cover] rect in
                NSColor.windowBackgroundColor.withAlphaComponent(0.95).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 36, height: 36), xRadius: 6, yRadius: 6).addClip()
                cover.draw(in: NSRect(x: 4, y: 4, width: 36, height: 36))
                NSGraphicsContext.restoreGraphicsState()
                let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
                (track.title as NSString).draw(in: NSRect(x: 48, y: 13, width: 184, height: 18), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: NSColor.labelColor, .paragraphStyle: style
                ])
                return true
            }
            item.setDraggingFrame(NSRect(x: location.x - 22, y: location.y - 22, width: size.width, height: size.height), contents: image)
            let session = beginDraggingSession(with: [item], event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
            return nil
        default: break
        }
        return event
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        pressed = nil; pressedTrack = nil; Self.active = nil; Self.mouseDown = nil
        NotificationCenter.default.post(name: .trackDragEnded, object: nil)
    }
}

struct PlaylistDropLabel: View {
    let playlist: Playlist
    @Bindable var model: AppModel
    @ViewState<Bool> private var targeted = false
    @ViewState<Bool> private var added = false
    @ViewState<UUID?> private var receipt = nil
    @ViewState<Bool> private var receiving = false
    var body: some View {
        Label(playlist.name, systemImage: added ? "checkmark.circle.fill" : (targeted ? "plus.circle.fill" : "music.note.list"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .background(targeted ? BMusicTheme.pink.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .onDrop(of: [UTType.bmusicTrack.identifier], isTargeted: $targeted) { providers in
                targeted = false
                guard !receiving, !providers.isEmpty else { return false }
                receiving = true
                Task { @MainActor in
                    defer { receiving = false; targeted = false }
                    do {
                        var tracks: [Track] = []
                        for provider in providers.prefix(100) {
                            let data: Data = try await withCheckedThrowingContinuation { continuation in
                                provider.loadDataRepresentation(forTypeIdentifier: UTType.bmusicTrack.identifier) { data, error in
                                    if let data { continuation.resume(returning: data) }
                                    else { continuation.resume(throwing: error ?? BMusicError.invalidResponse) }
                                }
                            }
                            tracks.append(try TrackDragPayload.decode(data))
                        }
                        if model.addTracks(tracks, to: playlist.id) { receipt = UUID(); added = true }
                    } catch { model.error = "添加歌曲失败：\(error.localizedDescription)" }
                }
                return true
            }
            .onReceive(NotificationCenter.default.publisher(for: .trackDragEnded)) { _ in targeted = false }
            .task(id: receipt) {
                guard receipt != nil else { return }
                do { try await Task.sleep(for: .seconds(1.5)); added = false } catch {}
            }
            .help("拖动歌曲到这里加入歌单")
    }
}
