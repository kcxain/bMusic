# 性能与内存验证（0.1.0 / build 34）

## 实现与预算

- AppModel / Player 使用 Observation 按属性追踪。进度保留独立状态对象；暂停后相同时间值跳过发布。
- 音乐库后台串行加载、编码和原子写入；180ms 合并连续修改；revision 隔离过期保存，退出等待 flush。失败保留待保存快照并显示错误。
- 播放快照仅在正常退出时保存；进度更新、拖动、切歌和队列调整保留在内存。相同快照跳过文件写入。强制退出或断电恢复上次正常退出的快照。收藏和歌单修改仍及时保存。
- 队列条目拥有 UUID，重复歌曲按条目定位；分 P 和音源切换均带取消与过期结果检查。
- ResourcePool 统一处理共享请求、取消、调度和严格 LRU 成本预算。最后一个使用者取消后中止操作，实际退出后释放并发槽位。
- 图像解码缓存 8 MiB，最多 80 张；网络和解码最多 3 个并发。HTTP 内存缓存 0.5 MiB、磁盘缓存 48 MiB。系统封面与页面共用服务；内存压力时清空图像缓存。
- 音频分段缓存 4 MiB，最多 32 段、2 个并发请求；文件头缓存 0.5 MiB、最多 2 个。
- 接口响应缓存 0.75 MiB、最多 20 项、60 秒；分 P 元数据最多 32 项、1000 个曲目、15 分钟。
- 首页持久缓存最多 12 首和 256 KiB，先显示缓存，再刷新。
- 顺序播放剩余 20 秒时仅准备下一首元数据及 256 KiB 文件头；暂停、切歌或改变模式取消推测请求。

以上是缓存持有数据的预算。视图持有的可见图片、在途响应、AVFoundation 缓冲和系统渲染各自占用额外内存，因此预算之和不能作为进程总内存上限。

## 本次测量

- Release：10000 首收藏的后台保存，20 次，P50 17.79ms、P95 18.56ms。
- 1000 次 ResourcePool 热缓存查询合计 0.475ms，缓存数据 4096 字节。
- 已安装应用：30 个每秒 RSS 样本，中位数 153.06 MiB、峰值 159.89 MiB；采样期间用户仍在操作应用。RSS 与活动监视器的内存指标不同，也不代表播放/大量滚动下的峰值。
- 本地测试报告 41 项，包含按环境开关跳过的在线与性能测试；本地测试均通过。覆盖取消、并发、预算、失效、重复队列身份、保存失败重试、分页/分区缓存隔离、本机 HTTP 音频分段复用。
- 在线榜单成功返回 12 首；独立长音频验证在 `/x/web-interface/view` 返回 HTTP 412，尚未进入音频加载阶段。本次不声明新的真实网络播放提速比例。
- 已检查安装版可恢复播放队列与进度、暂停启动，并确认队列隐藏滚动条、删除按钮独立对齐。完整交互及长时间播放内存峰值仍需持续验证。

## 可复现检查

```sh
scripts/test.sh
BMUSIC_PERF_TESTS=1 scripts/test.sh -c release --filter PerformanceTests
BMUSIC_LIVE_TESTS=1 BMUSIC_AUDIO_ONLY=1 BMUSIC_TEST_BVID=BV1krsE6WEGn scripts/test.sh --filter testLiveSearchAndAudioPlayback
python3 scripts/sample-memory.py --seconds 30 --output /tmp/bmusic-memory.json
```

使用 Instruments 的 Points of Interest 记录 `BMusic operation` 区间，包含首个内容出现、搜索结果、点击到开始播放、跳转到恢复播放。`BMUSIC_METRICS=1` 启动进程时会额外打印耗时；首个内容出现指标以 SwiftUI onAppear 为终点，图片加载和窗口呈现另测。基准使用临时目录和固定数据，与真实音乐库隔离。
