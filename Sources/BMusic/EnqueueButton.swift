import SwiftUI

struct EnqueueButton: View {
    let isQueued: Bool
    let action: () -> Void
    var body: some View {
        Button {
            if !isQueued { action() }
        } label: {
            Image(systemName: isQueued ? "checkmark" : "plus")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 30, height: 32).contentShape(Rectangle())
                .iconHoverFeedback(color: isQueued ? BMusicTheme.pink : .secondary)
        }.buttonStyle(IconButtonStyle())
            .help(isQueued ? "已在播放队列中" : "加入播放队列")
            .accessibilityLabel(isQueued ? "已在播放队列中" : "加入播放队列")
    }
}
