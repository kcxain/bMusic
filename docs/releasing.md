# 发布维护

BMusic 使用 Sparkle 2.10.1（Package.resolved 固定依赖），支持 macOS 14+。构建时嵌入 Sparkle.framework 和安装辅助程序，添加 Frameworks rpath，最后统一 ad-hoc 签名。Developer ID 签名和公证尚未配置，首次安装可能受到 Gatekeeper 提示；更新后的钥匙串访问可能要求重新授权。

## 更新与信任

- 应用内置 Ed25519 公钥，更新包在解压前验证签名。默认每日自动检查，用户确认后安装；设置提供自动检查开关。
- Feed 地址：`https://github.com/kcxain/bMusic/releases/latest/download/appcast.xml`。每次正式 Release 都应包含完整 appcast、安装包和 SHA256SUMS.txt，发布前完成附件上传。
- `SUShowReleaseNotes=false` 关闭 Sparkle 的内嵌更新说明，维持无 WebView 的应用界面。发布说明在 GitHub 查看。
- 安装时走正常退出流程，等待播放状态和音乐库保存。0.1.0 需要先手动安装包含 Sparkle 的版本。
- 发布私钥只保存在本机钥匙串，账户名 `io.github.kcxain.BMusic`。请使用 Sparkle `generate_keys -x` 导出到离线加密备份；将备份存放在仓库之外，迁移机器时通过 `-f` 导入。当前未将私钥上传到 GitHub。

参考 [Magpie 的更新签名验证](https://github.com/yetone/magpie/blob/main/internal/update/signed.go) 的内置公钥和发布端签名原则；BMusic 的下载、安装和重启由 Sparkle 实现。参见 [Sparkle 官方文档](https://sparkle-project.org/documentation/)。

## 发布步骤

1. `git pull --rebase`，修改版本号与递增的 CFBundleVersion。
2. `scripts/test.sh`，`scripts/build-app.sh`。
3. `python3 scripts/package-release.py`：检查钥匙串公钥与应用一致，校验应用签名，生成 ZIP、Ed25519 签名、appcast 和 SHA256SUMS.txt，再验证更新包签名。
4. 提交、推送并等待 CI 成功。创建与版本匹配的 v 标签。
5. 创建 GitHub 草稿 Release，上传生成的三个附件。确认完整后发布为 Latest。发布完成后的 ZIP 保持不变，修改包内容需要重新签名。
6. 从已安装的旧版本检查更新，验证下载、安装、重启和状态恢复。已签名包的验证可本地执行；完整升级验证需要两个版本的应用。

## CI

矩阵测试 Xcode 16.4 / 26.0。旧编译器使用原生 Material 与系统按钮样式，Xcode 26+ 编译 Liquid Glass 并在 macOS 26+ 启用。`#available` 负责运行时分支，`#if compiler(>=6.2)` 负责旧 SDK 编译兼容。正式安装包使用新 SDK 构建。

图片解码留在 ResourcePool 的后台任务，返回的缓存包装类型跨任务传输；公开 NSImage 加载接口和 NowPlaying ArtworkLoader 均隔离到 MainActor，避免旧 SDK 的非 Sendable 警告。
