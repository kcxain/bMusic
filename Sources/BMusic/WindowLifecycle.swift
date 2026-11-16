import AppKit
import SwiftUI
import BMusicCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var memoryPressure: DispatchSourceMemoryPressure?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { Task { await ArtworkService.shared.trim() } }
        source.resume(); memoryPressure = source
    }
    var reopenMainWindow: (() -> Void)?
    var flushLibrary: (() async throws -> Void)?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let flushLibrary else { return .terminateNow }
        Task {
            do { try await flushLibrary(); sender.reply(toApplicationShouldTerminate: true) }
            catch {
                let alert = NSAlert()
                alert.messageText = "应用状态保存失败"
                alert.informativeText = "\(error.localizedDescription)\n留在应用中可重试保存。"
                alert.addButton(withTitle: "留在应用")
                alert.addButton(withTitle: "退出")
                sender.reply(toApplicationShouldTerminate: alert.runModal() == .alertSecondButtonReturn)
            }
        }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopenMainWindow?()
        sender.activate(ignoringOtherApps: true)
        return false
    }
}

struct MainWindowContent: View {
    @Bindable var model: AppModel
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        ContentView(model: model, player: model.player)
            .frame(minWidth: 940, minHeight: 640)
            .tint(BMusicTheme.pink)
            .onAppear {
                if !model.firstContentReported {
                    model.firstContentReported = true
                    PerformanceTrace.end(model.launchTrace)
                }
                let action = openWindow
                delegate.reopenMainWindow = { action(id: "main") }
                delegate.flushLibrary = {
                    try await model.player.flushPlaybackSession()
                    try await model.flushLibrary()
                }
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
    }
}
