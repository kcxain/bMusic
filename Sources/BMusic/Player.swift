import Observation
import AppKit
import AVFoundation
import MediaPlayer
import BMusicCore

@MainActor
@Observable
final class Player {
    var current: Track?
    private(set) var queue: [QueueEntry] = [] {
        didSet {
            let ids = Set(queue.map { $0.track.id })
            if ids != queuedTrackIDs { queuedTrackIDs = ids }
            sessionChanged()
        }
    }
    private(set) var queuedTrackIDs: Set<String> = []
    var index = 0
    var isPlaying = false
    var isLoading = false
    let timeline = PlaybackTimeline()
    private let nowPlaying = NowPlayingPublisher()
    var elapsed: Double { timeline.elapsed }
    var duration: Double { timeline.duration }
    var streams: [AudioStream] = []
    var selectedStream: AudioStream?
    var error: String?
    var mode: PlaybackMode = .sequential { didSet { clearPrefetch(); sessionChanged() } }
    var volume: Double = 0.8 { didSet { engine.volume = Float(volume); sessionChanged() } }
    var preferHiRes = UserDefaults.standard.object(forKey: "preferHiRes") as? Bool ?? true {
        didSet { UserDefaults.standard.set(preferHiRes, forKey: "preferHiRes") }
    }
    var onPlayed: ((Track) -> Void)?
    private let client: BilibiliClient
    let engine = AVPlayer()
    @ObservationIgnored private var audioAsset: IndexedAudioAsset?
    @ObservationIgnored private var assetTask: Task<Void, Never>?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var rateObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var failureObserver: NSObjectProtocol?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var installation = UUID()
    @ObservationIgnored private var playTrace: PerformanceTrace.Span?
    @ObservationIgnored private var seekTrace: PerformanceTrace.Span?
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    @ObservationIgnored private var prefetched: (Track, [AudioStream], Date)?
    @ObservationIgnored private var prefetchAttempt: UUID?
    @ObservationIgnored private var attemptedURLs: [URL] = []
    @ObservationIgnored private var resumePosition = 0.0
    private(set) var intendsPlayback = false
    @ObservationIgnored private let sessionStore = PlaybackSessionStore()
    @ObservationIgnored private var restoreTask: Task<Void, Never>?
    @ObservationIgnored private var sessionRevision: UInt64 = 0
    @ObservationIgnored private var restoringSession = false
    @ObservationIgnored private var sessionWritable = true
    @ObservationIgnored private var needsResume = false
    @ObservationIgnored private var restoredQualityID: Int?
    private(set) var sessionError: String?
    @ObservationIgnored private var commandTargets: [(MPRemoteCommand, Any)] = []

    init(client: BilibiliClient) {
        self.client = client
        engine.volume = Float(volume)
        engine.automaticallyWaitsToMinimizeStalling = false
        timeObserver = engine.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            // AVPlayer guarantees this callback runs on the supplied main queue.
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.engine.currentItem?.status == .readyToPlay {
                    self.timeline.tick(time.seconds, item: self.engine.currentItem)
                }
                self.updateNowPlaying()
                self.prefetchUpcomingIfNeeded()
            }
        }
        rateObservation = engine.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let status = self.engine.timeControlStatus
                self.isPlaying = self.current != nil && status == .playing
                if self.isPlaying {
                    if let span = self.playTrace { PerformanceTrace.end(span); self.playTrace = nil }
                    if let span = self.seekTrace { PerformanceTrace.end(span); self.seekTrace = nil }
                }
                self.isLoading = !self.needsResume && self.current != nil && self.error == nil && (self.engine.currentItem?.status != .readyToPlay || status == .waitingToPlayAtSpecifiedRate)
                self.updateNowPlaying(force: true)
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self, let item = notification.object as? AVPlayerItem, item === self.engine.currentItem else { return }
                if self.mode == .repeatOne { self.seek(0) } else { self.next(automatic: true) }
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self, let item = notification.object as? AVPlayerItem, item === self.engine.currentItem else { return }
                self.retryOrFail(item.error?.localizedDescription ?? "音频连接中断，请重试。")
            }
        }
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand) { $0.setPlaying(true) }
        register(center.pauseCommand) { $0.setPlaying(false) }
        register(center.togglePlayPauseCommand) { $0.toggle() }
        register(center.nextTrackCommand) { $0.next() }
        register(center.previousTrackCommand) { $0.previous() }
        let target = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(event.positionTime) }; return .success
        }
        commandTargets.append((center.changePlaybackPositionCommand, target))
        restoreTask = Task { [weak self] in await self?.restorePlaybackSession() }
    }

    private func register(_ command: MPRemoteCommand, action: @escaping @MainActor (Player) -> Void) {
        let target = command.addTarget { [weak self] _ in
            Task { @MainActor in if let self { action(self) } }; return .success
        }
        commandTargets.append((command, target))
    }
    func state(for track: Track) -> TrackPlaybackState {
        TrackPlaybackState(trackID: track.id, currentID: current?.id,
                           intendsPlayback: intendsPlayback, failed: error != nil)
    }
    func activate(_ track: Track, in tracks: [Track]? = nil) {
        if state(for: track).shouldToggle { toggle() }
        else { play(track, in: tracks) }
    }
    func activateSearchResult(_ track: Track) {
        if state(for: track).shouldToggle { toggle(); return }
        let position = QueueEditing.selectSingle(track, in: &queue)
        playEntry(at: position)
    }
    func activateEntry(_ id: UUID) {
        guard let position = queue.firstIndex(where: { $0.id == id }) else { return }
        if position == index, current != nil, error == nil { toggle() }
        else { playEntry(at: position) }
    }
    func state(for entry: QueueEntry) -> TrackPlaybackState {
        guard queue.indices.contains(index), queue[index].id == entry.id else { return .idle }
        return state(for: entry.track)
    }
    func play(_ track: Track, in tracks: [Track]? = nil) {
        if let tracks { queue = QueueEditing.uniqueEntries(from: tracks) }
        if let i = queue.firstIndex(where: { $0.track.id == track.id }) { playEntry(at: i) }
        else { queue = [QueueEntry(track: track)]; playEntry(at: 0) }
    }
    private func playEntry(at position: Int, resumeAt seconds: Double = 0, qualityID: Int? = nil) {
        guard queue.indices.contains(position) else { return }
        if let playTrace { PerformanceTrace.end(playTrace, outcome: "superseded") }
        if let seekTrace { PerformanceTrace.end(seekTrace, outcome: "superseded"); self.seekTrace = nil }
        playTrace = PerformanceTrace.begin("click_to_playing")
        needsResume = false; restoredQualityID = nil
        index = position
        let entryID = queue[position].id, track = queue[position].track
        let warm = prefetched.flatMap { $0.0.id == track.id && Date().timeIntervalSince($0.2) < 40 ? $0 : nil }
        clearPrefetch()
        task?.cancel(); assetTask?.cancel(); let token = UUID(); generation = token
        engine.pause(); engine.replaceCurrentItem(with: nil); audioAsset = nil
        current = track; timeline.reset(duration: track.duration); timeline.tick(seconds, item: nil); error = nil; isLoading = true
        nowPlaying.setTrack(track)
        selectedStream = nil; streams = []; intendsPlayback = true
        sessionChanged()
        task = Task {
            do {
                let resolved: Track
                if let warm { resolved = warm.0 }
                else if track.cid != nil { resolved = track }
                else {
                    let details = try await client.details(track)
                    resolved = details.tracks.first(where: { $0.part == track.part }) ?? details.tracks[0]
                }
                let available: [AudioStream]
                if let warm { available = warm.1 }
                else { available = try await client.audio(resolved) }
                try Task.checkCancellation()
                guard generation == token else { return }
                guard queue.indices.contains(index), queue[index].id == entryID else { return }
                current = resolved; queue[index].track = resolved; streams = available
                timeline.reset(duration: resolved.duration)
                timeline.tick(seconds, item: nil)
                nowPlaying.setTrack(resolved)
                guard let stream = available.first(where: { $0.id == qualityID }) ?? AudioStream.preferred(in: available, hiRes: preferHiRes) else { throw BMusicError.noAudio }
                install(stream, at: seconds); onPlayed?(resolved)
            } catch is CancellationError {} catch {
                guard generation == token else { return }
                self.error = error.localizedDescription; isLoading = false
                updateNowPlaying(force: true)
            }
        }
    }
    func choose(_ stream: AudioStream) { install(stream, at: elapsed) }
    private func install(_ stream: AudioStream, at position: Double) {
        selectedStream = stream; attemptedURLs = []; resumePosition = position; error = nil
        sessionChanged()
        installURL(stream.url)
    }
    private func installURL(_ url: URL) {
        attemptedURLs.append(url); isLoading = true
        engine.pause(); engine.replaceCurrentItem(with: nil); audioAsset = nil
        timeline.reset(duration: duration)
        timeline.tick(resumePosition, item: nil)
        assetTask?.cancel()
        let token = generation, sourceToken = UUID()
        installation = sourceToken
        assetTask = Task {
            do {
                let source = try await IndexedAudioAsset.prepare(url: url)
                try Task.checkCancellation()
                guard token == generation, installation == sourceToken else { return }
                attach(source)
            } catch is CancellationError {} catch {
                guard token == generation, installation == sourceToken, !Task.isCancelled else { return }
                retryOrFail(error.localizedDescription)
            }
        }
    }
    private func attach(_ source: IndexedAudioAsset) {
        audioAsset = source
        let item = AVPlayerItem(asset: source.asset)
        item.preferredForwardBufferDuration = 6
        let token = generation, sourceToken = installation
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.installation == sourceToken, self.engine.currentItem === item else { return }
                if item.status == .failed { self.retryOrFail(item.error?.localizedDescription ?? "音频加载失败") }
                else if item.status == .readyToPlay {
                    self.isLoading = false
                    if self.resumePosition > 0 { self.seek(self.resumePosition); self.resumePosition = 0 }
                    else if self.intendsPlayback { self.engine.play() }
                    self.updateNowPlaying()
                }
            }
        }
        engine.replaceCurrentItem(with: item)
        if intendsPlayback && resumePosition == 0 { engine.play() }
    }
    private func retryOrFail(_ message: String) {
        if let next = selectedStream?.backups.first(where: { !attemptedURLs.contains($0) }) {
            resumePosition = elapsed; installURL(next)
        } else { error = message; isLoading = false; engine.pause() }
    }
    func retry() {
        if current != nil { playEntry(at: index, resumeAt: elapsed, qualityID: selectedStream?.id ?? restoredQualityID) }
    }
    func toggle() {
        guard current != nil else { if !queue.isEmpty { playEntry(at: 0) }; return }
        setPlaying(!intendsPlayback)
    }
    private func setPlaying(_ value: Bool) {
        if value, needsResume {
            playEntry(at: index, resumeAt: elapsed, qualityID: restoredQualityID)
            return
        }
        intendsPlayback = value
        sessionChanged()
        if !value { clearPrefetch() }
        if value && !timeline.isSeeking && !timeline.isScrubbing { engine.play() }
        else { engine.pause() }
        updateNowPlaying(force: true)
    }
    func previewSeek(_ seconds: Double) {
        if !timeline.isScrubbing { engine.pause() }
        timeline.scrub(to: seconds)
    }
    func cancelScrub() {
        timeline.cancelScrub()
        if intendsPlayback { engine.play() }
    }
    func seek(_ seconds: Double) {
        if needsResume {
            let request = timeline.seek(to: seconds)
            _ = timeline.complete(request, actual: timeline.elapsed)
            sessionChanged(); updateNowPlaying(force: true)
            return
        }
        guard let item = engine.currentItem, item.status == .readyToPlay else {
            timeline.cancelScrub(); return
        }
        if let seekTrace { PerformanceTrace.end(seekTrace, outcome: "superseded") }
        seekTrace = PerformanceTrace.begin("seek_to_resume")
        let request = timeline.seek(to: seconds)
        sessionChanged()
        let target = timeline.elapsed
        engine.pause()
        item.cancelPendingSeeks()
        updateNowPlaying(force: true)
        // A quarter-second tolerance avoids unnecessary exact-sample decoding on long streams.
        let tolerance = CMTime(seconds: 0.25, preferredTimescale: 600)
        engine.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self, weak item] finished in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, item === self.engine.currentItem,
                      self.timeline.complete(request, actual: self.engine.currentTime().seconds) else { return }
                if self.intendsPlayback && !self.timeline.isScrubbing { self.engine.play() }
                if !self.intendsPlayback, let span = self.seekTrace { PerformanceTrace.end(span, outcome: "paused"); self.seekTrace = nil }
                if !finished { self.error = "跳转中断，请重试。" }
                self.updateNowPlaying(force: true)
            }
        }
    }
    func next(automatic: Bool = false) {
        guard !queue.isEmpty else { return }
        if mode == .shuffle, queue.count > 1 {
            let choice = Int.random(in: 0..<queue.count - 1)
            playEntry(at: choice >= index ? choice + 1 : choice); return
        }
        if index + 1 < queue.count { playEntry(at: index + 1) }
        else if !automatic { playEntry(at: 0) }
        else { intendsPlayback = false; engine.pause(); isPlaying = false }
    }
    func previous() {
        if elapsed > 3 { seek(0); return }
        guard !queue.isEmpty else { return }; playEntry(at: max(0, index - 1))
    }
    func enqueue(_ track: Track) { QueueEditing.selectSingle(track, in: &queue) }
    func moveEntry(_ id: UUID, to boundary: Int) {
        let currentID = queue.indices.contains(index) ? queue[index].id : nil
        QueueEditing.move(&queue, id: id, to: boundary)
        if let currentID, let position = queue.firstIndex(where: { $0.id == currentID }) { index = position }
        clearPrefetch()
    }
    func removeEntry(_ id: UUID) {
        guard let removedIndex = queue.firstIndex(where: { $0.id == id }) else { return }
        let currentID = queue.indices.contains(index) ? queue[index].id : nil
        let wasPlaying = intendsPlayback
        queue.remove(at: removedIndex); clearPrefetch()
        guard !queue.isEmpty else { clearQueue(); return }
        if currentID == id, current != nil {
            // Continue with the next entry, or the last remaining entry at the end.
            playEntry(at: min(removedIndex, queue.count - 1))
            if !wasPlaying { setPlaying(false) }
        } else if let currentID, let position = queue.firstIndex(where: { $0.id == currentID }) {
            index = position
        } else { index = min(index, queue.count - 1) }
    }
    func clearQueue() {
        generation = UUID(); installation = UUID()
        task?.cancel(); assetTask?.cancel(); clearPrefetch()
        intendsPlayback = false; engine.pause(); engine.replaceCurrentItem(with: nil)
        itemObservation = nil; audioAsset = nil
        queue = []; index = 0; current = nil; streams = []; selectedStream = nil
        error = nil; isLoading = false; isPlaying = false; resumePosition = 0
        timeline.reset(duration: 0); nowPlaying.clear()
        needsResume = false; restoredQualityID = nil; sessionChanged()
        if let playTrace { PerformanceTrace.end(playTrace, outcome: "cleared"); self.playTrace = nil }
        if let seekTrace { PerformanceTrace.end(seekTrace, outcome: "cleared"); self.seekTrace = nil }
    }
    private func clearPrefetch() {
        prefetchTask?.cancel(); prefetchTask = nil; prefetched = nil; prefetchAttempt = nil
    }
    private func prefetchUpcomingIfNeeded() {
        guard mode == .sequential, intendsPlayback, isPlaying, duration > 30,
              duration - elapsed < 20, duration - elapsed > 0,
              queue.indices.contains(index + 1), prefetchAttempt == nil else { return }
        let next = queue[index + 1], token = generation
        prefetchAttempt = next.id
        prefetchTask = Task {
            do {
                var track = next.track
                if track.cid == nil {
                    let details = try await client.details(track)
                    track = details.tracks.first(where: { $0.part == track.part }) ?? details.tracks[0]
                }
                let streams = try await client.audio(track)
                try Task.checkCancellation()
                guard generation == token, mode == .sequential,
                      let stream = AudioStream.preferred(in: streams, hiRes: preferHiRes) else { return }
                prefetched = (track, streams, Date())
                try await IndexedAudioAsset.prefetchHead(url: stream.url)
            } catch { /* Playback fetches fresh metadata when speculative preparation fails. */ }
        }
    }
    private func sessionChanged() {
        guard !restoringSession else { return }
        sessionRevision &+= 1
    }
    private var sessionSnapshot: PlaybackSession {
        PlaybackSession(tracks: queue.map(\.track), currentTrackID: current?.id, elapsed: elapsed,
                        mode: mode, volume: volume, qualityID: selectedStream?.id ?? restoredQualityID)
    }
    private func restorePlaybackSession() async {
        do {
            let snapshot = try await sessionStore.load()
            // User actions while disk I/O is in flight take precedence.
            if sessionRevision == 0, let snapshot {
                restoringSession = true
                queue = QueueEditing.uniqueEntries(from: snapshot.tracks)
                mode = snapshot.mode; volume = snapshot.volume
                if let position = queue.firstIndex(where: { $0.track.id == snapshot.currentTrackID }) {
                    index = position; current = queue[position].track
                    timeline.reset(duration: current!.duration)
                    timeline.tick(snapshot.elapsed, item: nil)
                    needsResume = true; restoredQualityID = snapshot.qualityID
                    nowPlaying.setTrack(current!); updateNowPlaying(force: true)
                }
                restoringSession = false
            }
        } catch {
            sessionWritable = false
            sessionError = "播放记录读取失败，原文件已保留：\(error.localizedDescription)"
        }
    }
    func flushPlaybackSession() async throws {
        await restoreTask?.value
        guard sessionWritable else { return }
        sessionRevision &+= 1
        try await sessionStore.save(sessionSnapshot, revision: sessionRevision)
    }

    private func updateNowPlaying(force: Bool = false) {
        nowPlaying.update(elapsed: elapsed, duration: duration,
                          playing: intendsPlayback && isPlaying && !timeline.isSeeking && !timeline.isScrubbing, force: force)
    }
}
