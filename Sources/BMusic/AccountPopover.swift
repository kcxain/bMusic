import SwiftUI

struct AccountPopover: View {
    @Bindable var model: AppModel
    let dismiss: () -> Void
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        MusicPopover(title: "账号") {
            VStack(spacing: 2) {
                if model.profile == nil {
                    PopoverAction(title: "扫码登录", symbol: "qrcode") { dismiss(); model.showingLogin = true }
                } else {
                    PopoverAction(title: "切换账号", symbol: "arrow.triangle.2.circlepath") {
                        dismiss(); model.logout(switchAccount: true)
                    }
                    PopoverAction(title: "退出登录", symbol: "rectangle.portrait.and.arrow.right") {
                        dismiss(); model.logout()
                    }
                }
                Divider().padding(.vertical, 4)
                PopoverAction(title: "设置", symbol: "gearshape") { dismiss(); openSettings() }
            }
        }.frame(width: 220)
    }
}
