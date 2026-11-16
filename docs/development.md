## 开发与验证

使用 Swift 6+ / Xcode 26+ 或兼容的 Command Line Tools。可以在 Xcode 打开 `Package.swift`。

```bash
swift build
./scripts/test.sh
BMUSIC_LIVE_TESTS=1 ./scripts/test.sh
./scripts/build-app.sh
```

`test.sh` 自动兼容部分 Command Line Tools 的 Swift Testing 宏搜索路径。普通测试覆盖 WBI 签名、搜索标题处理、音轨解析与选择、分 P 标识、本地库去重与持久化、损坏文件保留。联网测试会请求二维码、检索公开视频、解析音频轨，并使用静音 AVPlayer 验证播放进度推进与跳转到 60 秒后继续播放。

构建脚本输出当前 CPU 架构的本地签名 `.app`。正式分发建议配置 Developer ID 签名和 Apple 公证。

```text
Sources/BMusic/           SwiftUI 界面、应用状态、AVPlayer、系统媒体控制
Sources/BMusicCore/       B 站 API、WBI 签名、数据模型、钥匙串、本地 JSON 库
Tests/BMusicCoreTests/    核心与联网测试
resources/               App 信息和图标
scripts/                 构建、测试、图标生成
```

## 存储与内存设计

- 音乐库：`~/Library/Application Support/BMusic/library.json`，原子写入；读取失败时保留原文件并停用写入。
- 凭据：macOS 钥匙串 `io.github.kcxain.BMusic`，网络会话使用内存 Cookie。
- 每页最多 20 条搜索结果，延迟创建曲目行；封面请求 160px 缩略图。
- 读取 fMP4 `sidx` 分段索引，以 HLS 描述原始音频片段；仅绑定 `127.0.0.1` 的原生服务按 HTTP Range 读取所需片段，路径使用随机令牌，音频字节保持原样；AVPlayer 按流缓冲，前向缓冲目标 6 秒，切歌时释放上一条播放项；仅选取音频轨 URL。
- 解码图片缓存 8 MiB、音频片段 4 MiB、文件头 512 KiB、接口响应 768 KiB；图片 HTTP 内存缓存 512 KiB、磁盘缓存 48 MiB。缓存预算与进程总内存分别统计。
- 播放队列、进度、音量、模式与音质选择仅在正常退出时写入 `playback.json`；播放期间保留在内存，重开后暂停恢复。强制退出或断电将恢复上次正常退出时的快照。
- 收藏、歌单和最近播放在数据发生变化时合并保存；最近播放上限 100 首。搜索历史上限 20 条。
- 音频片段仅保存在内存，切歌释放旧播放器与本地服务。构建临时图标目录自动清理。

## 验证记录

见 [性能与发布检查](docs/performance.md)。代码内包含存储、队列、请求取消、缓存预算和本机音频传输回归测试。真实网络表现取决于 B 站接口、账号权益及 CDN。


