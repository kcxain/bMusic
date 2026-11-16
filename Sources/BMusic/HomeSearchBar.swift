import SwiftUI

struct HomeSearchBar: View {
    @Bindable var model: AppModel
    @ViewState<Bool> private var showingHistory = false
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16)).foregroundStyle(.secondary)
                TextField("搜索歌曲、歌手", text: $model.query)
                    .font(.system(size: 15)).textFieldStyle(.plain)
                    .onSubmit { model.search() }
                    .accessibilityLabel("搜索歌曲、歌手，按回车搜索")
                if !model.query.isEmpty {
                    MusicIconButton(symbol: "xmark.circle.fill", label: "清除搜索并返回推荐",
                                    color: .secondary, size: 14, width: 24, height: 30) { model.resetSearch() }
                }
                Divider().frame(height: 20)
                Button {
                    model.musicOnly.toggle()
                    if model.searched { model.search() }
                } label: {
                    Text(model.musicOnly ? "音乐分区" : "全部分区")
                        .font(.system(size: 13, weight: .medium))
                        .frame(minHeight: 32).contentShape(Rectangle()).iconHoverFeedback(color: .secondary)
                }
                .buttonStyle(.plain).fixedSize()
                .help(model.musicOnly ? "点击切换到全部分区" : "点击切换到音乐分区")
                .accessibilityLabel("搜索范围")
                .accessibilityValue(model.musicOnly ? "音乐分区" : "全部分区")
            }
            .padding(.horizontal, 16).frame(height: model.searched ? 38 : 40)
            .musicGlass(cornerRadius: 20)
            MusicIconButton(symbol: "clock.arrow.circlepath", label: "搜索历史", color: .secondary,
                            size: 19, width: 24, height: 32) { showingHistory = true }
            .musicPopover(isPresented: $showingHistory, edge: .bottom) {
                SearchHistoryView(model: model, didSelect: { showingHistory = false })
                    .frame(width: 320, height: min(300, 58 + CGFloat(max(1, model.searchHistory.count)) * 33))
            }
        }
    }
}
