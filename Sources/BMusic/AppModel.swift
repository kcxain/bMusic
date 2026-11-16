import Observation
import AppKit
import BMusicCore

@MainActor
@Observable
final class AppModel {
    let client = BilibiliClient()
    @ObservationIgnored let launchTrace = PerformanceTrace.begin("launch_to_first_content")
    @ObservationIgnored var firstContentReported = false
    private let persistence = LibraryPersistence()
    private let discoveryCache = DiscoveryCache()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var partsTask: Task<Void, Never>?
    @ObservationIgnored private var partsID = UUID()
    private(set) var libraryReady = false
    private let historyStore = SearchHistory()
    var searchHistory: [String] = []
    @ObservationIgnored lazy var player = Player(client: client)
    var library = Library() {
        didSet { favoriteIDs = Set(library.favorites.map(\.id)) }
    }
    private(set) var favoriteIDs: Set<String> = []
    var profile: UserProfile?
    var results: [Track] = []
    var query = ""
    var musicOnly = true
    var searching = false
    var searched = false
    var page = 1
    var totalPages = 1
    var error: String?
    var showingLogin = false
    var selection: String? = "home"
    var recommendations: [Track] = []
    var loadingRecommendations = false
    var recommendationError: String?
    @ObservationIgnored private var recommendationDate: Date?
    var parts: [Track] = []
    var showingParts = false
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchID = UUID()
    @ObservationIgnored private var libraryWritable = false
    init() {
        searchHistory = historyStore.entries
        player.onPlayed = { [weak self] track in self?.editLibrary { $0.record(track) } }
        Task {
            do { library = try await persistence.load(); libraryWritable = true }
            catch { self.error = "音乐库读取失败，原文件已保留：\(error.localizedDescription)" }
            libraryReady = true
        }
        Task {
            do { try await client.restoreSession(); profile = try await client.profile() }
            catch { self.error = error.localizedDescription }
        }
    }
    func loadRecommendations(force: Bool = false) async {
        guard !loadingRecommendations else { return }
        if !force, let date = recommendationDate, Date().timeIntervalSince(date) < 900 { return }
        loadingRecommendations = true; recommendationError = nil
        defer { loadingRecommendations = false }
        if recommendations.isEmpty, let cached = await discoveryCache.load() { recommendations = cached }
        do {
            recommendations = try await client.musicRanking()
            await discoveryCache.save(recommendations)
            recommendationDate = Date()
        } catch { recommendationError = error.localizedDescription }
    }
    func editLibrary(_ edit: (inout Library) -> Void) {
        guard libraryWritable else { error = libraryReady ? "音乐库暂时无法写入，请检查原文件。" : "音乐库正在加载，请稍后重试。"; return }
        var updated = library; edit(&updated)
        library = updated; revision &+= 1
        let snapshot = updated, currentRevision = revision
        saveTask?.cancel()
        saveTask = Task {
            await persistence.stage(snapshot, revision: currentRevision)
            do {
                try await Task.sleep(for: .milliseconds(180))
                try Task.checkCancellation()
                try await persistence.flush()
            } catch is CancellationError {} catch {
                self.error = "音乐库修改尚未保存：\(error.localizedDescription)"
            }
        }
    }
    func flushLibrary() async throws {
        guard libraryWritable else { return }
        saveTask?.cancel()
        await persistence.stage(library, revision: revision)
        try await persistence.flush()
    }
    func addTracks(_ tracks: [Track], to playlist: UUID) -> Bool {
        guard libraryWritable, library.playlists.contains(where: { $0.id == playlist }) else { return false }
        editLibrary { library in for track in tracks { library.add(track, to: playlist) } }
        return true
    }
    func favorite(_ track: Track) { editLibrary { $0.toggleFavorite(track) } }
    func createPlaylist(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let playlist = Playlist(name: name)
        editLibrary { $0.playlists.append(playlist) }; selection = playlist.id.uuidString
    }
    func removeSearchHistory(_ query: String) {
        historyStore.remove(query); searchHistory = historyStore.entries
    }
    func clearSearchHistory() {
        historyStore.clear(); searchHistory = historyStore.entries
    }
    func resetSearch() {
        searchTask?.cancel(); searchID = UUID()
        query = ""; results = []; searched = false; searching = false; error = nil
        page = 1; totalPages = 1
    }
    func search(page: Int = 1) {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        searchTask?.cancel(); let token = UUID(); searchID = token
        selection = "home"; searching = true; searched = true; error = nil
        if page == 1 {
            results = []; historyStore.record(keyword); searchHistory = historyStore.entries
        }
        let musicOnly = musicOnly
        searchTask = Task {
            let trace = PerformanceTrace.begin("search_results")
            defer { PerformanceTrace.end(trace, outcome: Task.isCancelled ? "cancelled" : "completed") }
            do {
                let response = try await client.search(keyword, page: page, musicOnly: musicOnly)
                try Task.checkCancellation()
                guard token == searchID else { return }
                results = response.tracks; self.page = page; totalPages = response.totalPages; searching = false
            } catch is CancellationError {} catch {
                guard token == searchID else { return }
                self.error = error.localizedDescription; searching = false
            }
        }
    }
    func loadParts(_ track: Track) {
        partsTask?.cancel(); let token = UUID(); partsID = token
        partsTask = Task {
            do {
                let details = try await client.details(track)
                try Task.checkCancellation()
                guard partsID == token else { return }
                parts = details.tracks; showingParts = true
            } catch is CancellationError {} catch {
                guard partsID == token else { return }
                self.error = error.localizedDescription
            }
        }
    }
    private(set) var changingAccount = false
    func logout(switchAccount: Bool = false) {
        guard !changingAccount else { return }
        changingAccount = true
        Task {
            defer { changingAccount = false }
            do {
                try await client.logout(); profile = nil
                if switchAccount { showingLogin = true }
            }
            catch { self.error = error.localizedDescription }
        }
    }
}
