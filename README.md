# BMusic

原生 macOS B 站音乐播放器。SwiftUI 界面、AVFoundation 音频播放、URLSession 网络请求，零第三方运行时依赖，无 WebView。最低 macOS 14。

## 安装

从 Releases 下载 `BMusic-0.1.0-macOS-arm64.zip`，解压后将 BMusic.app 放入 Applications。首版适用于 Apple Silicon、macOS 14 及以上；macOS 26 及以上启用 Liquid Glass。安装包使用本地 ad-hoc 签名，尚未经过 Developer ID 签名和 Apple 公证。

## 使用

```bash
./scripts/build-app.sh
open dist/BMusic.app
```

左下角登录入口显示 B 站二维码，使用哔哩哔哩 App 扫码确认。输入歌名或歌手并回车搜索，双击结果或点击播放按钮开始播放。右键曲目可加入歌单、加入队列、选择分 P 或在 B 站打开。

- 搜索：音乐分区 / 全部分区、分页、视频合集分 P。
- 播放：独立音频轨、播放队列、上一首 / 下一首、进度拖动、音量、随机播放、单曲循环、系统媒体键与正在播放信息。
- 音质：直接播放 B 站 DASH 音频原始流，提供实际可用的流畅、标准、高音质、Hi-Res 和 Dolby 选项，显示编码与返回码率。默认优先选择最高可用音质。
- 音乐库：收藏、创建 / 重命名 / 删除本地歌单、添加 / 移除曲目、最近播放 100 首。
- 账号：扫码登录、钥匙串保存凭据、重启恢复登录、退出清除本机凭据；会话到期后重新扫码。

Hi-Res 的可用性取决于音源与账号权益。B 站通常将无损音轨放在 `dash.flac.audio` 中；应用仅在接口实际返回时提供相应选项。最终输出还受 macOS 混音器、音频 MIDI 输出设置和设备能力影响。首版提供源音质播放，硬件独占输出与自动切换设备采样率留待后续开发。

收藏与歌单属于 BMusic 本地音乐库，B 站收藏夹同步属于后续范围。搜索标题和作者沿用视频元数据，作者表示上传者。B 站公开 Web 接口可能调整或触发风控，应用会展示对应错误。

## 开发与验证

使用 Swift 6+ / Xcode 26+ 或兼容的 Command Line Tools。可以在 Xcode 打开 `Package.swift`。

```bash
swift build
./scripts/test.sh
BMUSIC_LIVE_TESTS=1 ./scripts/test.sh
./scripts/build-app.sh
```

`test.sh` 自动兼容部分 Command Line Tools 的 Swift Testing 宏搜索路径。普通测试覆盖 WBI 签名、搜索标题处理、音轨解析与选择、分 P 标识、本地库去重与持久化、损坏文件保留。联网测试会请求二维码、检索公开视频、解析音频轨，并使用静音 AVPlayer 验证播放进度推进与跳转到 60 秒后继续播放。

构建脚本输出当前 CPU 架构的本地签名 `.app`。正式向其他用户分发需要 Developer ID 签名和 Apple 公证。

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


## 参考

交互与功能规划参考 [mygo-cloudmusic](https://github.com/cfour-hi/mygo-cloudmusic)。本项目采用独立编写的 Swift 实现。
