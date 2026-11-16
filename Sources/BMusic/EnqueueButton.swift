import SwiftUI

struct EnqueueButton: View {
    let isQueued: Bool
    var color: Color = .secondary
    let action: () -> Void
    var body: some View {
        MusicIconButton(symbol: isQueued ? "checkmark" : "plus", label: isQueued ? "已在播放队列中" : "加入播放队列",
                        color: isQueued ? BMusicTheme.pink : color, size: 16, width: 30, height: 32) {
            if !isQueued { action() }
        }
    }
}
