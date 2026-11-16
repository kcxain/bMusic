import SwiftUI

struct QualityPopover: View {
    @Bindable var player: Player
    let dismiss: () -> Void
    var body: some View {
        MusicPopover(title: "音质") {
            if player.streams.isEmpty {
                Text("播放歌曲后选择音质").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(player.streams) { stream in
                        PopoverAction(title: stream.detail, selected: player.selectedStream?.id == stream.id) {
                            dismiss()
                            if player.selectedStream?.id != stream.id { player.choose(stream) }
                        }
                    }
                }
            }
        }.frame(width: 260)
    }
}
