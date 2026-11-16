# 音质与原生播放验证

BMusic 请求 Bilibili 网页播放接口返回的 DASH 音轨，包括常规 audio、flac.audio 和 dolby.audio。播放仅使用音频 URL；按 sidx 描述原始 fMP4 分段并交给 AVFoundation AVPlayer。转发保持音频字节与时间戳，应用没有再编码步骤。

## 本次实测

使用已登录会话请求真实音源，静音 AVPlayer 逐轨验证时间推进，并对比第一个 CDN 音频段与本机转发段的每个字节：

| 音轨 | 编码 | 系统识别 | 原始片段一致 | 原生播放 |
| --- | --- | --- | --- | --- |
| 30251 Hi-Res | fLaC | 48 kHz / 双声道 | 通过 | 通过 |
| 30250 Dolby | ec-3 | 48 kHz / 6 声道 | 通过 | 通过 |
| 30280 / 30232 / 30216 | AAC | 48 kHz / 双声道 | 通过 | 通过 |

这些是抽样音源的结果。压缩格式描述中的 bitsPerChannel 返回 0，不能用它断言原始有效位深。Hi-Res 标识对应 B 站实际返回的音轨档位，采样率和位深依具体音源而定。

## 与网页端及输出设备的关系

应用使用同一网页音轨来源，转发音频数据保持一致。网页端选择同一档位、返回相同资源时，源音频一致；本次没有对浏览器输出 PCM 进行逐样本比较。系统混音、音量、重采样、耳机传输和设备设置会影响最终输出。

Dolby 音轨已验证原生 ec-3 解码与六声道识别。Atmos 对象元数据、空间音频渲染和最终输出模式尚未验证，因此菜单使用“Dolby 音轨”。最终输出使用系统默认设备和采样率；端到端无损需要与音源匹配的设备链路验证。

## 复现

```sh
BMUSIC_QUALITY_AUDIT=1 scripts/test.sh --filter AudioQualityLiveTests
BMUSIC_QUALITY_AUDIT=1 BMUSIC_QUALITY_SEARCH='杜比全景声 音乐' scripts/test.sh --filter AudioQualityLiveTests
```

测试使用本机钥匙串会话，不输出 Cookie、账号资料或签名 CDN URL。通过 BMUSIC_TEST_BVID 可选择其他公开音源；测试在默认 CI 中关闭。
