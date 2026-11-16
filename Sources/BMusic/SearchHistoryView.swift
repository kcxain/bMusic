import SwiftUI

struct SearchHistoryView: View {
    @Bindable var model: AppModel
    var didSelect: () -> Void = {}
    var body: some View {
        MusicPopover(title: "最近搜索", clear: model.searchHistory.isEmpty ? nil : { model.clearSearchHistory() }) {
            if model.searchHistory.isEmpty {
                Text("搜索过的歌曲和歌手会出现在这里").foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.searchHistory, id: \.self) { query in
                            HStack(spacing: 4) {
                                PopoverAction(title: query, symbol: "clock") {
                                    didSelect(); model.query = query; model.search()
                                }
                                RemoveItemButton(help: "删除这条搜索历史") { model.removeSearchHistory(query) }
                            }
                        }
                    }
                }
            }
        }
    }
}
