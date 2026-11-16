import SwiftUI
import AppKit

// Explicit alias retains the property-wrapper API across SDK versions.
typealias ViewState<Value> = SwiftUI.State<Value>

@main
struct BMusicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ViewState private var model = AppModel()
    @StateObject private var updater = AppUpdater()
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }
    var body: some Scene {
        Window("BMusic", id: "main") {
            MainWindowContent(model: model, delegate: delegate)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新…") { updater.check() }.disabled(!updater.canCheck)
            }
            CommandMenu("播放") {
                Button("播放 / 暂停") { model.player.toggle() }.keyboardShortcut(" ", modifiers: [])
                Button("下一首") { model.player.next() }.keyboardShortcut(.rightArrow, modifiers: .command)
                Button("上一首") { model.player.previous() }.keyboardShortcut(.leftArrow, modifiers: .command)
            }
        }
        Settings {
            SettingsView(player: model.player, updater: updater)
        }
    }
}

struct SettingsView: View {
    @Bindable var player: Player
    @ObservedObject var updater: AppUpdater
    var body: some View {
        Form {
            Section("更新") {
                Toggle("自动检查更新", isOn: $updater.automaticallyChecks)
                Button("检查更新…") { updater.check() }.disabled(!updater.canCheck)
            }
            Section("音频") {
                Toggle("优先选择 Hi-Res / Dolby 音源", isOn: $player.preferHiRes)
                Text("音质以 B 站实际返回的音轨为准，Hi-Res 通常需要大会员和对应音源。播放时可在底部菜单切换音质。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("BMusic 直接播放原始音频流。系统输出采样率可在 macOS「音频 MIDI 设置」中配置。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("储存") {
                Text("收藏、歌单与最近播放保存在本机；登录凭据保存在系统钥匙串。")
                Button("打开音乐库文件夹") {
                    NSWorkspace.shared.open(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BMusic"))
                }
            }
        }.formStyle(.grouped).frame(width: 480, height: 420)
    }
}
