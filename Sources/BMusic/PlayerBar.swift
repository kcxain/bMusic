import SwiftUI
import BMusicCore

struct PlayerBar: View {
    @Bindable var player: Player
    @Bindable var model: AppModel
    @ViewState<Bool> private var showQueue = false
    @ViewState<Bool> private var showQuality = false
    var body: some View {
        VStack(spacing: 4) {
            if let error = player.error ?? player.sessionError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).lineLimit(2)
                    Spacer()
                    if player.error != nil { Button("重试") { player.retry() } }
                }.font(.caption).foregroundStyle(.orange)
            }
            PlayerControlsLayout {
                trackInfo.clipped()
                transport.fixedSize()
                accessories.fixedSize()
            }
            SeekBar(timeline: player.timeline, trackID: player.current?.id,
                    preview: player.previewSeek, commit: player.seek, cancel: player.cancelScrub)
        }
        .padding(.horizontal, 18).padding(.vertical, 9)
    }
    private var trackInfo: some View {
        HStack(spacing: 10) {
            Group {
                if let track = player.current { Artwork(url: track.cover, size: 38).draggableTrack(track) }
                else { Artwork(url: nil, size: 38) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(player.current?.title ?? "选一首喜欢的音乐")
                    .font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.tail)
                Text(player.current?.uploader ?? "BMusic")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

        }.padding(.trailing, 14)
    }
    private var transport: some View {
        HStack(spacing: 4) {
            MusicIconButton(symbol: player.mode.symbol, label: "\(player.mode.label)；点击切换为\(player.mode.next.label)",
                            color: player.mode == .sequential ? .secondary : BMusicTheme.pink, size: 15) {
                player.mode = player.mode.next
            }.accessibilityLabel("播放模式").accessibilityValue(player.mode.label)
            MusicIconButton(symbol: "backward.end.fill", label: "上一首", width: 36) { player.previous() }
            MusicIconButton(symbol: player.intendsPlayback ? "pause.fill" : "play.fill", label: "播放 / 暂停",
                            size: 16, width: 36, prominent: true, loading: player.isLoading) { player.toggle() }
                .disabled(player.current == nil)
            MusicIconButton(symbol: "forward.end.fill", label: "下一首", width: 36) { player.next() }
            favoriteButton
        }
    }
    private var accessories: some View {
        HStack(spacing: 4) { quality; volume; queueButton }
    }
    private var favoriteButton: some View {
        let liked = player.current.map { model.favoriteIDs.contains($0.id) } ?? false
        return MusicIconButton(symbol: liked ? "heart.fill" : "heart", label: liked ? "取消喜欢" : "喜欢",
                               color: liked ? BMusicTheme.pink : .secondary, size: 18) {
            if let track = player.current { model.favorite(track) }
        }.disabled(player.current == nil || !model.libraryReady)
    }
    private var quality: some View {
        Button { showQuality.toggle() } label: {
            Text(player.selectedStream?.label ?? "音质").font(.system(size: 13, weight: .semibold))

                .padding(.horizontal, 7).frame(minHeight: 30).contentShape(Rectangle())
                .iconHoverFeedback(color: player.selectedStream?.isHiRes == true ? BMusicTheme.memberGold : .primary)
        }.buttonStyle(.plain).fixedSize()
            .musicPopover(isPresented: $showQuality) {
                QualityPopover(player: player) { showQuality = false }
            }
    }
    private var volume: some View {
        HStack(spacing: 6) {
            Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 16)).foregroundStyle(.secondary)
            Slider(value: $player.volume, in: 0...1)
                .controlSize(.small).frame(minWidth: 44, idealWidth: 52, maxWidth: 56).frame(height: 28).accessibilityLabel("音量")
        }.help("音量 \(Int(player.volume * 100))%")
    }
    private var queueButton: some View {
        MusicIconButton(symbol: "list.bullet", label: "播放队列", color: .secondary, size: 20) { showQueue = true }
            .musicPopover(isPresented: $showQueue) {
                PlaybackQueueView(player: player)
                    .frame(width: 340, height: min(320, 58 + CGFloat(max(1, player.queue.count)) * 44))
            }
    }
}
