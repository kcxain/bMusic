import SwiftUI
import BMusicCore

struct DiscoveryView: View {
    @Bindable var model: AppModel
    @Bindable var player: Player
    var bottomClearance: CGFloat = 0
    private var recent: [Track] { model.library.recent }

    var body: some View {
        GeometryReader { geometry in
            let featured = CarouselMetrics(viewport: geometry.size.width, featured: true)
            let recentMetrics = CarouselMetrics(viewport: geometry.size.width, featured: false)
            let featuredWidth = featured.cardWidth
            let recentWidth = recentMetrics.cardWidth
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 16) {
                        Button { model.selection = "recent" } label: {
                            HStack(spacing: 7) {
                                Text("最近听过").font(.system(size: 20, weight: .bold))
                                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                            }.foregroundStyle(.primary)
                        }.buttonStyle(.plain).padding(.horizontal, 28)
                        if recent.isEmpty {
                            Text("听过的歌曲会出现在这里").font(.callout).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading).padding(.horizontal, 28)
                        } else {
                            CoverCarousel(tracks: recent, cardWidth: recentWidth, coverHeight: recentMetrics.coverHeight, viewportWidth: geometry.size.width) { _, track in
                                RecentTrackCard(track: track, width: recentWidth, state: player.state(for: track), isQueued: player.queuedTrackIDs.contains(track.id), enqueue: { player.enqueue(track) }) {
                                    player.activate(track)
                                }.contextMenu { trackActions(track) }.draggableTrack(track)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("热门推荐").font(.system(size: 20, weight: .bold)).padding(.horizontal, 28)
                        if model.loadingRecommendations && model.recommendations.isEmpty {
                            HStack(spacing: 18) {
                                ForEach(0..<3) { _ in
                                    ArtworkPlaceholder()
                                        .frame(width: featuredWidth, height: featuredWidth * 1.33)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }.overlay { ProgressView() }.padding(.leading, 28)
                        } else if let error = model.recommendationError, model.recommendations.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("推荐暂时无法加载").font(.headline)
                                Text(error).font(.callout).foregroundStyle(.secondary)
                                Button("重试") { Task { await model.loadRecommendations(force: true) } }
                            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 28)
                        } else {
                            CoverCarousel(tracks: model.recommendations, cardWidth: featuredWidth, coverHeight: featured.coverHeight, viewportWidth: geometry.size.width) { index, track in
                                FeaturedCard(track: track, rank: index + 1, state: player.state(for: track), width: featuredWidth, isQueued: player.queuedTrackIDs.contains(track.id), enqueue: { player.enqueue(track) }) {
                                    player.activate(track)
                                }.contextMenu { trackActions(track) }.draggableTrack(track)
                            }
                        }
                    }
                }.padding(.bottom, bottomClearance + 24)
            }
        }
        .task { await model.loadRecommendations() }
    }
    @ViewBuilder private func trackActions(_ track: Track) -> some View {
        Button(player.state(for: track).label) { player.activate(track) }
        Button("加入播放队列") { player.enqueue(track) }
        Button(model.favoriteIDs.contains(track.id) ? "取消喜欢" : "喜欢") { model.favorite(track) }
        Menu("加入歌单") {
            ForEach(model.library.playlists) { list in
                Button(list.name) { model.editLibrary { $0.add(track, to: list.id) } }
            }
        }
    }
}

private struct FeaturedCard: View {
    let track: Track
    let rank: Int
    let state: TrackPlaybackState
    let width: CGFloat
    let isQueued: Bool
    let enqueue: () -> Void
    let play: () -> Void
    @ViewState<Bool> private var hovering = false
    var body: some View {
        Button(action: play) {
            ZStack(alignment: .bottomLeading) {
                CachedArtwork(url: track.cover, pixels: 640)
                    .frame(width: width, height: width * 1.33).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.12), .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 5) {
                    Text("音乐榜 · 第 \(rank) 名").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    Text(track.title).font(.system(size: 15, weight: .bold)).lineLimit(2)
                    Text(track.uploader).font(.system(size: 13, weight: .medium)).lineLimit(1).foregroundStyle(.white.opacity(0.9))
                }.foregroundStyle(.white).padding(18).padding(.bottom, 44)
                if hovering {
                    Image(systemName: state.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).musicGlass(cornerRadius: 17, interactive: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(14)
                }
            }.frame(width: width, height: width * 1.33)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.06), lineWidth: 0.5))
        }.buttonStyle(.plain)
            .overlay(alignment: .bottomTrailing) {
                if hovering {
                    EnqueueButton(isQueued: isQueued, action: enqueue).foregroundStyle(.white)
                        .musicGlass(cornerRadius: 16, interactive: true).padding(14)
                }
            }
            .onHover { hovering = $0 }.help("\(state.label) \(track.title)")
    }
}

private struct RecentTrackCard: View {
    let track: Track
    let width: CGFloat
    let state: TrackPlaybackState
    let isQueued: Bool
    let enqueue: () -> Void
    let play: () -> Void
    @ViewState<Bool> private var hovering = false
    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 6) {
                Artwork(url: track.cover, size: width)
                    .overlay(alignment: .bottomLeading) {
                        if hovering {
                            Image(systemName: state.symbol)
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 32, height: 32).musicGlass(cornerRadius: 16, interactive: true).padding(9)
                        }
                    }.padding(.bottom, 3)
                Text(track.title).font(.system(size: 13, weight: .medium)).foregroundStyle(state.isCurrent ? BMusicTheme.pink : .primary)
                    .lineLimit(1)
                Text(track.uploader).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(width: width, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                if hovering {
                    EnqueueButton(isQueued: isQueued, action: enqueue).foregroundStyle(.white)
                        .musicGlass(cornerRadius: 16, interactive: true)
                        .padding(9)
                        .frame(height: width, alignment: .bottomTrailing)
                }
            }
            .onHover { hovering = $0 }.help("\(state.label) \(track.title)")
    }
}
