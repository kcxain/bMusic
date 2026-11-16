import SwiftUI
import BMusicCore

private let accent = BMusicTheme.pink

struct ContentView: View {
    @ViewState private var showingAccount = false
    @Bindable var model: AppModel
    @Bindable var player: Player
    @ViewState<Bool> private var newPlaylist = false
    @ViewState<String> private var playlistName = ""
    @ViewState<UUID?> private var renameID = nil
    @ViewState<UUID?> private var deleteID = nil
    @ViewState<CGFloat> private var playerClearance = 110
    private var playlist: Playlist? { model.library.playlists.first { $0.id.uuidString == model.selection } }
    private var title: String {
        switch model.selection {
        case "home": return "主页"
        case "favorites": return "我喜欢的"
        case "recent": return "最近播放"
        default: return playlist?.name ?? "发现音乐"
        }
    }
    private var tracks: [Track] {
        switch model.selection {
        case "favorites": return model.library.favorites
        case "recent": return model.library.recent
        case "home": return model.results
        default: return playlist?.tracks ?? []
        }
    }
    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let error = model.error {
                    HStack {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        Text(error).font(.callout).textSelection(.enabled)
                        Spacer()
                        MusicIconButton(symbol: "xmark", label: "关闭提示") { model.error = nil }
                    }.padding(12).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 28).padding(.bottom, 12)
                }
                Group {
                    if model.selection == "home", !model.searched {
                        discovery
                    } else if model.searching && model.selection == "home" {
                        ProgressView("正在检索 B 站音乐…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if tracks.isEmpty {
                        emptyLibrary
                    } else {
                        trackList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .bottom) {
                PlayerBar(player: player, model: model)
                    .musicGlass(cornerRadius: 28)
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 44).padding(.bottom, 12).padding(.top, 6)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: PlayerClearanceKey.self, value: geometry.size.height)
                        }
                    }
            }
            .onPreferenceChange(PlayerClearanceKey.self) { playerClearance = $0 }
        }
        .toolbarBackground(.automatic, for: .windowToolbar)
        .sheet(isPresented: $model.showingLogin) { LoginView(model: model) }
        .sheet(isPresented: $model.showingParts) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("选择分 P / 曲目").font(.title2.bold()); Spacer(); Button("完成") { model.showingParts = false } }
                List(model.parts) { track in
                    HStack {
                        Text("P\(track.part)").foregroundStyle(.secondary).frame(width: 35)
                        Text(track.title).lineLimit(2)
                        Spacer()
                        MusicIconButton(symbol: player.state(for: track).symbol, label: player.state(for: track).label) { model.player.activate(track); model.showingParts = false }
                        MusicIconButton(symbol: model.favoriteIDs.contains(track.id) ? "heart.fill" : "heart", label: "喜欢", color: model.favoriteIDs.contains(track.id) ? accent : .secondary) { model.favorite(track) }
                        EnqueueButton(isQueued: player.queuedTrackIDs.contains(track.id)) { player.enqueue(track) }
                        Menu { ForEach(model.library.playlists) { list in Button(list.name) { model.editLibrary { $0.add(track, to: list.id) } } } } label: { Image(systemName: "text.badge.plus").iconHoverFeedback(color: .secondary) }
                    }
                }
            }.padding(24).frame(width: 720, height: 450)
        }
        .alert(renameID == nil ? "新建歌单" : "重命名歌单", isPresented: $newPlaylist) {
            TextField("歌单名称", text: $playlistName)
            Button("取消", role: .cancel) { renameID = nil }
            Button("保存") {
                if let id = renameID {
                    let name = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { model.editLibrary { library in if let index = library.playlists.firstIndex(where: { $0.id == id }) { library.playlists[index].name = name } } }
                } else { model.createPlaylist(playlistName) }
                renameID = nil
            }
        }
        .confirmationDialog("删除这张本地歌单？", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
            Button("删除歌单", role: .destructive) {
                if let id = deleteID { model.editLibrary { $0.playlists.removeAll { $0.id == id } }; model.selection = "home" }
                deleteID = nil
            }
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $model.selection) {
                Label("主页", systemImage: "house").tag("home")
                Label("我喜欢的", systemImage: "heart").tag("favorites")
                Label("最近播放", systemImage: "clock").tag("recent")
                Section {
                    ForEach(model.library.playlists) { list in
                        PlaylistDropLabel(playlist: list, model: model).tag(list.id.uuidString)
                            .contextMenu {
                                Button("重命名") { renameID = list.id; playlistName = list.name; newPlaylist = true }
                                Button("删除歌单", role: .destructive) { deleteID = list.id }
                            }
                    }
                    Button { playlistName = ""; renameID = nil; newPlaylist = true } label: { Label("新建歌单", systemImage: "plus").iconHoverFeedback(color: .secondary) }.buttonStyle(.plain).foregroundStyle(.secondary)
                } header: { Text("我的歌单") }
            }.listStyle(.sidebar)
            Divider().padding(.horizontal, 16)
            HStack(spacing: 10) {
                Button { showingAccount.toggle() } label: {
                    AccountAvatar(url: model.profile?.avatar, isVIP: model.profile?.isVIP == true)
                        .frame(width: 42, height: 42).contentShape(Circle())
                }
                .buttonStyle(IconButtonStyle()).frame(width: 42, height: 42)
                .disabled(model.changingAccount)
                .help("账号与设置").accessibilityLabel("账号菜单")
                .musicPopover(isPresented: $showingAccount) {
                    AccountPopover(model: model) { showingAccount = false }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.profile?.name ?? "登录 B 站账号")
                        .font(.callout.weight(.medium)).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(model.profile?.name ?? "登录 B 站账号")
                    if model.profile?.isVIP == true {
                        Text("大会员").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BMusicTheme.memberGold)
                    } else if model.profile == nil {
                        Text("扫码连接你的音乐世界").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
            }.padding(16)
        }.frame(maxHeight: .infinity, alignment: .top)
            .navigationSplitViewColumnWidth(min: 180, ideal: 195, max: 270)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 24) {
            if model.selection != "home" || !model.searched {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 34, weight: .bold)).lineLimit(1)
                    if model.selection != "home" {
                        Text("\(tracks.count) 首歌曲").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if model.selection != "home", !tracks.isEmpty {
                    Button { player.play(tracks[0], in: tracks) } label: { Label("播放全部", systemImage: "play.fill") }.musicGlassButton(prominent: true)
                }
            }
            }
            if model.selection == "home" {
                HomeSearchBar(model: model)
                    .padding(.top, model.searched ? 0 : 4)
                    .padding(.bottom, model.searched ? 0 : 2)
            }
        }.padding(.horizontal, 28).padding(.top, 6)
            .padding(.bottom, model.selection == "home" && model.searched ? 12 : 24)
    }
    private var emptyLibrary: some View {
        VStack(spacing: 14) {
            Image(systemName: model.selection == "favorites" ? "heart" : (model.selection == "home" ? "magnifyingglass" : "music.note.list"))
                .font(.system(size: 36, weight: .light)).foregroundStyle(accent.opacity(0.75))
                .padding(.bottom, 4)
            Text(model.selection == "home" ? "换个关键词试试" : "从一首喜欢的歌开始")
                .font(.title3.weight(.semibold))
            Text(model.selection == "home" ? "搜索歌名、歌手，或切换全部分区。" : "发现喜欢的音乐，点击爱心即可收藏。")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if model.selection != "home" {
                Button("发现音乐") { model.selection = "home" }.musicGlassButton().padding(.top, 6)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var discovery: some View {
        DiscoveryView(model: model, player: player, bottomClearance: playerClearance)
    }
    private var trackList: some View {
        VStack(spacing: 0) {
            HStack { Text("歌曲"); Spacer(); Text("时长").padding(.trailing, 124) }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 40).padding(.bottom, 10)
            Divider().padding(.horizontal, 28)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(track: track, number: index + 1, state: player.state(for: track), liked: model.favoriteIDs.contains(track.id), isQueued: player.queuedTrackIDs.contains(track.id), play: { activateListedTrack(track) }, favorite: { model.favorite(track) }, enqueue: { player.enqueue(track) })
                            .contextMenu {
                                Button(player.state(for: track).label) { activateListedTrack(track) }
                                Button("加入播放队列") { player.enqueue(track) }
                                Button("查看分 P / 曲目") { model.loadParts(track) }
                                Menu("加入歌单") {
                                    ForEach(model.library.playlists) { list in Button(list.name) { model.editLibrary { $0.add(track, to: list.id) } } }
                                }
                                if let playlist {
                                    Button("从歌单移除", role: .destructive) { model.editLibrary { library in if let i = library.playlists.firstIndex(where: { $0.id == playlist.id }) { library.playlists[i].tracks.removeAll { $0.id == track.id } } } }
                                }
                                Divider()
                                Link("在 B 站打开", destination: track.webURL)
                            }
                    }
                    if model.selection == "home", model.totalPages > 1 {
                        HStack {
                            Button("上一页") { model.search(page: model.page - 1) }.disabled(model.page <= 1)
                            Text("\(model.page) / \(model.totalPages)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            Button("下一页") { model.search(page: model.page + 1) }.disabled(model.page >= model.totalPages)
                        }.musicGlassButton().padding(12)
                    }
                }.padding(.horizontal, 24).padding(.top, 8)
                    .padding(.bottom, playerClearance + 8)
            }
        }
    }
    private func activateListedTrack(_ track: Track) {
        player.activate(track, in: playlist?.tracks)
    }
}

private struct PlayerClearanceKey: PreferenceKey {
    static var defaultValue: CGFloat = 110
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct Artwork: View {
    let url: URL?
    var size: CGFloat = 44
    var body: some View {
        CachedArtwork(url: url, pixels: size <= 80 ? 160 : 400)
            .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct TrackRow: View {
    let track: Track
    let number: Int
    let state: TrackPlaybackState
    let liked: Bool
    let isQueued: Bool
    let play: () -> Void
    let favorite: () -> Void
    let enqueue: () -> Void
    @ViewState<Bool> private var hovering = false
    var body: some View {
        HStack(spacing: 14) {
            Button(action: play) {
                Group {
                    if hovering || state.isCurrent {
                        Image(systemName: state.symbol).font(.system(size: 18, weight: .semibold))
                    } else { Text(String(format: "%02d", number)).font(.caption).monospacedDigit() }
                }.frame(width: 36, height: 40).contentShape(Rectangle())
                    .iconHoverFeedback(color: state.isCurrent ? accent : .secondary)
            }.buttonStyle(IconButtonStyle()).help(state.label).accessibilityLabel(state.label)
            HStack(spacing: 14) {
                Artwork(url: track.cover)
                VStack(alignment: .leading, spacing: 5) {
                    Text(track.title).font(.system(size: 13, weight: .medium)).foregroundStyle(state.isCurrent ? accent : .primary).lineLimit(1)
                    Text(track.uploader).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.contentShape(Rectangle()).onTapGesture(count: 2, perform: play)
                .draggableTrack(track)
            Text(TextFormatting.time(track.duration)).font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 54)
            Button(action: favorite) {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 40, height: 40).contentShape(Rectangle())
                    .iconHoverFeedback(color: liked ? accent : .secondary)
            }.buttonStyle(IconButtonStyle()).help(liked ? "取消喜欢" : "喜欢")
                .accessibilityLabel(liked ? "取消喜欢" : "喜欢")
            EnqueueButton(isQueued: isQueued, action: enqueue).foregroundStyle(.secondary)
        }.padding(.horizontal, 12).padding(.vertical, 9).background(state.isCurrent ? accent.opacity(0.07) : (hovering ? Color.primary.opacity(0.035) : .clear), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle()).onHover { hovering = $0 }
    }
}
