import SwiftUI
import CoreImage.CIFilterBuiltins
import BMusicCore

struct LoginView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ViewState<NSImage?> private var image = nil
    @ViewState<String> private var status = "正在生成二维码…"
    @ViewState<Bool> private var expired = false
    @ViewState<UUID> private var attempt = UUID()
    var body: some View {
        VStack(spacing: 20) {
            HStack { Spacer(); MusicIconButton(symbol: "xmark", label: "关闭", action: { dismiss() }) }
            Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 36)).foregroundStyle(.tint)
            Text("连接你的 bilibili").font(.title2.bold())
            Text("使用哔哩哔哩 App 扫码，并在手机上确认登录").font(.callout).foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.white)
                if let image { Image(nsImage: image).interpolation(.none).resizable().scaledToFit().padding(16) }
                else { ProgressView() }
            }.frame(width: 220, height: 220)
            Text(status).font(.callout).multilineTextAlignment(.center)
            if expired { Button("刷新二维码") { attempt = UUID() }.buttonStyle(.borderedProminent) }
            Text("登录凭据保存在 macOS 钥匙串中。\n收藏和歌单保存在此 Mac 上。")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(28).frame(width: 420)
            .task(id: attempt) { await login() }
    }
    private func login() async {
        expired = false; image = nil; status = "正在生成二维码…"
        do {
            let qr = try await model.client.generateQR()
            try Task.checkCancellation()
            let filter = CIFilter.qrCodeGenerator(); filter.message = Data(qr.url.utf8)
            guard let output = filter.outputImage,
                  let cg = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) else { throw BMusicError.invalidResponse }
            image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            status = "等待扫码"
            for _ in 0..<90 {
                try await Task.sleep(for: .seconds(2))
                let state = try await model.client.pollQR(key: qr.key)
                try Task.checkCancellation()
                switch state {
                case .waiting: status = "等待扫码"
                case .scanned: status = "扫码成功，请在手机上确认"
                case .expired: status = "二维码已过期，请刷新"; expired = true; return
                case .confirmed:
                    model.profile = try await model.client.profile()
                    guard model.profile != nil else { throw BMusicError.api(-101, "登录验证失败") }
                    dismiss(); return
                }
            }
            status = "二维码已过期，请刷新"; expired = true
        } catch is CancellationError {} catch { status = error.localizedDescription; expired = true }
    }
}
