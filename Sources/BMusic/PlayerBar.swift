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
            modeButton
            Button { player.previous() } label: { Image(systemName: "backward.end.fill").frame(width: 36, height: 36).contentShape(Rectangle()) }
                .help("上一首")
            Button { player.toggle() } label: {
                ZStack {
                    Circle().fill(BMusicTheme.pink).frame(width: 36, height: 36)
                    if player.isLoading { ProgressView().controlSize(.small).tint(.white) }
                    else { Image(systemName: player.intendsPlayback ? "pause.fill" : "play.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white) }
                }.contentShape(Circle())
            }.disabled(player.current == nil).help("播放 / 暂停")
            Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 36, height: 36).contentShape(Rectangle()) }
                .help("下一首")
            favoriteButton
        }.buttonStyle(IconButtonStyle()).font(.system(size: 17))
    }
    private var modeButton: some View {
        Button { player.mode = player.mode.next } label: {
            Image(systemName: player.mode.symbol).font(.system(size: 15, weight: .medium))
                .foregroundStyle(player.mode == .sequential ? .secondary : BMusicTheme.pink)
                .frame(width: 32, height: 36).contentShape(Rectangle())
        }.help("\(player.mode.label)；点击切换为\(player.mode.next.label)")
            .accessibilityLabel("播放模式").accessibilityValue(player.mode.label)
    }
    private var accessories: some View {
        HStack(spacing: 4) { quality; volume; queueButton }
    }
    private var favoriteButton: some View {
        let liked = player.current.map { model.favoriteIDs.contains($0.id) } ?? false
        return Button {
            if let track = player.current { model.favorite(track) }
        } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 32, height: 36).contentShape(Rectangle())
                .iconHoverFeedback(color: liked ? BMusicTheme.pink : .secondary)
        }.buttonStyle(IconButtonStyle())
            .disabled(player.current == nil || !model.libraryReady)
            .help(liked ? "取消喜欢" : "喜欢").accessibilityLabel(liked ? "取消喜欢" : "喜欢")
    }
    private var quality: some View {
        Button { showQuality.toggle() } label: {
            Text(player.selectedStream?.label ?? "音质").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(player.selectedStream?.isHiRes == true ? BMusicTheme.memberGold : .primary)
                .padding(.horizontal, 7).frame(minHeight: 30).contentShape(Rectangle())
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
        Button { showQueue = true } label: {
            Image(systemName: "list.bullet").font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 36).contentShape(Rectangle())
        }.buttonStyle(.plain).help("播放队列")
            .musicPopover(isPresented: $showQueue) {
                PlaybackQueueView(player: player)
                    .frame(width: 340, height: min(320, 58 + CGFloat(max(1, player.queue.count)) * 44))
            }
    }
}
