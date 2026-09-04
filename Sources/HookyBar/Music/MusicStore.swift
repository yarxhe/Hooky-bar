import Cocoa
import Combine
import MediaRemoteAdapter
import SwiftUI

enum MusicStoreDefaultsKey: String {
    case selectedMusicSource = "musicSource"
}

enum MusicStoreTiming {
    static let pollingInterval: TimeInterval = 1.0
    static let playbackClockInterval: TimeInterval = 0.5
    static let upcomingRefreshInterval: TimeInterval = 8.0
    static let likeStateRefreshInterval: TimeInterval = 2.5
    static let recoveryThrottleInterval: TimeInterval = 1.0
    static let playbackOverrideDuration: TimeInterval = 1.2
    static let likedOverrideDuration: TimeInterval = 1.5
    static let recoverySnapshotDelay: TimeInterval = 1.5
    static let navigationRefreshDelay: TimeInterval = 0.3
    static let likeRecoveryDelay: TimeInterval = 0.35
    static let launchPlaybackDelay: TimeInterval = 0.45
    static let retryPlaybackDelay: TimeInterval = 0.35
    static let postCommandSnapshotDelay: TimeInterval = 0.45
    static let launchPlaybackTimeout: TimeInterval = 25
    static let manualTrackIgnoreElapsedInterval: TimeInterval = 1.2
}

final class MusicStore: ObservableObject {
    @Published var isSelectedMusicAppRunning = false
    @Published var selectedMusicSource: MusicSource {
        didSet {
            UserDefaults.standard.set(selectedMusicSource.rawValue, forKey: MusicStoreDefaultsKey.selectedMusicSource.rawValue)
            adapterHasProvidedTrack = false
            activeMediaBundleIdentifier = nil
            selectedMusicProcessIdentifier = nil
            currentTrackIdentity = nil
            upcomingTrack = nil
            nowPlaying = NowPlayingSnapshot(artist: selectedMusicSource.fullTitle)
            isFetchingLikeState = false
            isFetchingUpcoming = false
            isFetchingSelectedPlaybackState = false
            expectedPlaybackState = nil
            playbackOverrideUntil = .distantPast
            playbackCommandGeneration += 1
            cancelPendingPlaybackStart()
            lastLikeStateRefresh = .distantPast
            lastUpcomingRefresh = .distantPast
            refreshMusicState()
            refreshMediaSnapshot()
        }
    }
    @Published var nowPlaying = NowPlayingSnapshot()
    @Published var upcomingTrack: UpcomingTrack?
    @Published var spectrum: [CGFloat] = Array(repeating: 0.08, count: 12)
    @Published var audioLevel: CGFloat = 0
    @Published var visualizerColors: [Color] = [.yellow, .orange]
    @Published var audioActive = false
    @Published var musicPresentationActive = false
    @Published var compactPlaybackActive = false
    @Published var controlPulse = 0
    @Published var trackNavigationDirection = 1
    @Published var trackPresentationRevision = 0
    @Published var artworkPresentationRevision = 0
    let spectrumSignal = AudioSpectrumSignal.shared
    var timer: Timer?
    var playbackClock: Timer?
    var workspaceObservers: [NSObjectProtocol] = []
    var isMonitoring = false
    var lastPlaybackTick = Date()
    var isFetchingNowPlaying = false
    var isFetchingUpcoming = false
    var isFetchingMediaSnapshot = false
    var isFetchingLikeState = false
    var isFetchingSelectedPlaybackState = false
    var lastLikeStateRefresh = Date.distantPast
    var lastUpcomingRefresh = Date.distantPast
    var likedOverrideUntil: Date?
    var expectedPlaybackState: Bool?
    var playbackOverrideUntil = Date.distantPast
    var playbackCommandGeneration = 0
    var pendingPlaybackStartToken: UUID?
    var pendingPlaybackStartInFlightToken: UUID?
    var pendingPlaybackStartDeadline = Date.distantPast
    var pendingPlaybackStartWorkItem: DispatchWorkItem?
    var manualTrackChangePending = false
    var ignoreRemoteElapsedUntil = Date.distantPast
    var adapterHasProvidedTrack = false
    var activeMediaBundleIdentifier: String?
    var selectedMusicProcessIdentifier: pid_t?
    var isScrubbingPlayback = false
    var isRecoveringPlayback = false
    var lastPlaybackRecovery = Date.distantPast
    var currentTrackIdentity: String?
    let adapterRegistry: MusicAdapterRegistry

    var activeAdapter: any MusicPlayerAdapter {
        adapterRegistry.adapter(for: selectedMusicSource)
    }

    var commandContext: MusicCommandContext {
        MusicCommandContext(ownsSystemMedia: selectedSourceOwnsSystemMedia)
    }

    init(adapterRegistry: MusicAdapterRegistry = MusicAdapterRegistry()) {
        self.adapterRegistry = adapterRegistry
        let saved = UserDefaults.standard.string(forKey: MusicStoreDefaultsKey.selectedMusicSource.rawValue)
        selectedMusicSource = MusicSource(rawValue: saved ?? "") ?? .yandex
        nowPlaying = NowPlayingSnapshot(artist: selectedMusicSource.fullTitle)
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        installWorkspaceObservers()
        adapterRegistry.startListening { [weak self] info in
            DispatchQueue.main.async { self?.applyTrackInfo(info) }
        }
        refreshMusicState()
        refreshNowPlaying()
        lastPlaybackTick = Date()
        refreshUpcomingTrack()
        updatePlaybackClockTimer()
        updatePollingTimer()
    }

    private func installWorkspaceObservers() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]
        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self,
                      let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication,
                      application.bundleIdentifier == self.selectedMusicSource.bundleIdentifier else { return }
                self.refreshMusicState()
                if name == NSWorkspace.didLaunchApplicationNotification {
                    self.resumePendingPlaybackStart()
                }
            }
        }
    }

    private func updatePollingTimer() {
        guard isMonitoring, isSelectedMusicAppRunning else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: MusicStoreTiming.pollingInterval, repeats: true) { [weak self] _ in
            // A one-shot MediaRemote request can return NIL while an already
            // running Electron player is handing media ownership back to
            // macOS. Keep retrying only until the selected player is bound;
            // after that the long-running listener and local clock take over.
            if let self, self.isSelectedMusicAppRunning, !self.selectedSourceOwnsSystemMedia {
                self.refreshMediaSnapshot()
                self.recoverSelectedPlaybackPresentation()
            }
            self?.refreshNowPlaying()
            self?.refreshSelectedPlaybackState()
            self?.refreshLikeState()
        }
    }

    private func updatePlaybackClockTimer() {
        guard isMonitoring, nowPlaying.isPlaying, nowPlaying.duration > 0 else {
            playbackClock?.invalidate()
            playbackClock = nil
            return
        }
        guard playbackClock == nil else { return }
        lastPlaybackTick = Date()
        playbackClock = Timer.scheduledTimer(
            withTimeInterval: MusicStoreTiming.playbackClockInterval,
            repeats: true
        ) { [weak self] _ in
            self?.tickPlaybackClock()
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        playbackClock?.invalidate()
        playbackClock = nil
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
        adapterRegistry.stopListening()
        cancelPendingPlaybackStart()
    }

    func tickPlaybackClock() {
        let now = Date()
        let delta = now.timeIntervalSince(lastPlaybackTick)
        lastPlaybackTick = now
        guard !isScrubbingPlayback, nowPlaying.isPlaying, nowPlaying.duration > 0 else { return }
        nowPlaying.elapsed = min(nowPlaying.duration, nowPlaying.elapsed + max(0, min(delta, 0.5)))
    }

    func refreshMusicState() {
        let application = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == selectedMusicSource.bundleIdentifier && !$0.isTerminated
        }
        guard let application else {
            isSelectedMusicAppRunning = false
            selectedMusicProcessIdentifier = nil
            if activeMediaBundleIdentifier != nil || currentTrackIdentity != nil {
                clearSelectedTrack()
            }
            updatePollingTimer()
            return
        }

        isSelectedMusicAppRunning = true
        updatePollingTimer()
        let didLaunch = application.processIdentifier != selectedMusicProcessIdentifier
        selectedMusicProcessIdentifier = application.processIdentifier
        if didLaunch {
            clearSelectedTrack()
            // MediaRemote's long-running listener may not emit an event when
            // The selected player can launch after Hooky Bar. Fetch a snapshot
            // to wake the island and let subsequent listener updates take over.
            refreshMediaSnapshot()
            DispatchQueue.main.asyncAfter(deadline: .now() + MusicStoreTiming.recoverySnapshotDelay) { [weak self] in
                guard let self, self.isSelectedMusicAppRunning else { return }
                self.refreshMediaSnapshot()
            }
        }
    }

    func refreshLocalizedContent() {
        guard currentTrackIdentity == nil else { return }
        nowPlaying.title = L10n.tr("music.nothingPlaying")
        nowPlaying.artist = selectedMusicSource.fullTitle
    }

    func refreshMediaSnapshot() {
        guard isSelectedMusicAppRunning, !isFetchingMediaSnapshot else { return }
        isFetchingMediaSnapshot = true
        adapterRegistry.requestSystemSnapshot { [weak self] info in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetchingMediaSnapshot = false
                self.applyTrackInfo(info)
            }
        }
    }

    func recoverSelectedPlaybackPresentation() {
        guard !isRecoveringPlayback,
              Date().timeIntervalSince(lastPlaybackRecovery) >= 1 else { return }
        isRecoveringPlayback = true
        lastPlaybackRecovery = Date()
        let source = selectedMusicSource
        let adapter = activeAdapter
        let context = commandContext
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let directSnapshot = adapter.directSnapshot(context: context)
            let playing = directSnapshot?.isPlaying ?? adapter.playbackState()
            DispatchQueue.main.async {
                self.isRecoveringPlayback = false
                guard self.selectedMusicSource == source,
                      self.isSelectedMusicAppRunning,
                      !self.selectedSourceOwnsSystemMedia,
                      let playing else { return }
                if let directSnapshot {
                    self.applyAdapterSnapshot(directSnapshot, marksSystemOwnership: false)
                    return
                }
                self.applyPlaybackState(playing)
                if !self.nowPlaying.isPlaying, self.currentTrackIdentity == nil {
                    self.clearSelectedTrack()
                }
            }
        }
    }

    func refreshLikeState(force: Bool = false) {
        guard isSelectedMusicAppRunning, !isFetchingLikeState,
              force || Date().timeIntervalSince(lastLikeStateRefresh) >= MusicStoreTiming.likeStateRefreshInterval else { return }
        isFetchingLikeState = true
        lastLikeStateRefresh = Date()
        let source = selectedMusicSource
        let adapter = activeAdapter
        let context = commandContext
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let state = adapter.ratingState(context: context)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetchingLikeState = false
                guard source == self.selectedMusicSource else { return }
                guard let state, self.likedOverrideUntil.map({ $0 <= Date() }) ?? true else { return }
                if self.nowPlaying.isLiked != state.liked { self.nowPlaying.isLiked = state.liked }
                if self.nowPlaying.isDisliked != state.disliked { self.nowPlaying.isDisliked = state.disliked }
            }
        }
    }

    func refreshUpcomingTrack() {
        guard isSelectedMusicAppRunning else { upcomingTrack = nil; return }
        guard activeAdapter.capabilities.canReadUpcomingTrack else { upcomingTrack = nil; return }
        guard !isFetchingUpcoming, Date().timeIntervalSince(lastUpcomingRefresh) >= MusicStoreTiming.upcomingRefreshInterval else { return }
        isFetchingUpcoming = true
        lastUpcomingRefresh = Date()
        let source = selectedMusicSource
        let adapter = activeAdapter
        let context = commandContext
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let upcoming = adapter.upcomingTrack(context: context)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetchingUpcoming = false
                guard self.selectedMusicSource == source else { return }
                if self.upcomingTrack != upcoming { self.upcomingTrack = upcoming }
            }
        }
    }

    func refreshNowPlaying() {
        guard isSelectedMusicAppRunning, selectedSourceOwnsSystemMedia,
              !adapterHasProvidedTrack, !isFetchingNowPlaying else { return }
        isFetchingNowPlaying = true
        let source = selectedMusicSource
        let adapter = activeAdapter
        let context = commandContext
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let snapshot = adapter.directSnapshot(context: context)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetchingNowPlaying = false
                guard self.selectedMusicSource == source,
                      !self.adapterHasProvidedTrack,
                      let snapshot else { return }
                self.applyAdapterSnapshot(snapshot, marksSystemOwnership: true)
            }
        }
    }

    func refreshSelectedPlaybackState() {
        guard isSelectedMusicAppRunning,
              selectedSourceOwnsSystemMedia, !isFetchingSelectedPlaybackState else { return }
        isFetchingSelectedPlaybackState = true
        let source = selectedMusicSource
        let adapter = activeAdapter
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let playing = adapter.playbackState()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetchingSelectedPlaybackState = false
                guard self.selectedMusicSource == source,
                      self.isSelectedMusicAppRunning,
                      self.selectedSourceOwnsSystemMedia,
                      let playing else { return }
                self.applyPlaybackState(playing)
            }
        }
    }

    func applyTrackInfo(_ info: TrackInfo?) {
        guard isSelectedMusicAppRunning else { return }
        guard let info, let snapshot = activeAdapter.snapshot(from: info) else {
            if activeMediaBundleIdentifier == selectedMusicSource.bundleIdentifier {
                activeMediaBundleIdentifier = nil
            }
            return
        }
        activeMediaBundleIdentifier = selectedMusicSource.bundleIdentifier
        adapterHasProvidedTrack = true
        applyAdapterSnapshot(snapshot, marksSystemOwnership: true)
    }

    func applyAdapterSnapshot(_ snapshot: MusicAdapterSnapshot, marksSystemOwnership: Bool) {
        let trackChanged = currentTrackIdentity != snapshot.identity
        let artworkArrived = !trackChanged && nowPlaying.artwork == nil && snapshot.artwork != nil
        let playing = resolvedPlaybackState(snapshot.isPlaying)
        let elapsed = trackChanged
            ? elapsedForChangedTrack(snapshot.elapsed)
            : resolvedElapsed(snapshot.elapsed, playing: playing)
        let duration = trackChanged
            ? max(0, snapshot.duration)
            : (snapshot.duration > 0 ? snapshot.duration : nowPlaying.duration)
        let rating = snapshot.rating
        let preserveLocalRating = likedOverrideUntil.map { $0 > Date() } == true
        nowPlaying = NowPlayingSnapshot(
            title: snapshot.title,
            artist: snapshot.artist,
            duration: duration,
            elapsed: duration > 0 ? min(elapsed, duration) : elapsed,
            isPlaying: playing,
            isLiked: preserveLocalRating ? nowPlaying.isLiked : (rating?.liked ?? (trackChanged ? false : nowPlaying.isLiked)),
            isDisliked: preserveLocalRating ? nowPlaying.isDisliked : (rating?.disliked ?? (trackChanged ? false : nowPlaying.isDisliked)),
            artwork: trackChanged ? snapshot.artwork : (snapshot.artwork ?? nowPlaying.artwork)
        )
        currentTrackIdentity = snapshot.identity
        if trackChanged { trackPresentationRevision &+= 1 }
        if trackChanged || artworkArrived { artworkPresentationRevision &+= 1 }
        if marksSystemOwnership { activeMediaBundleIdentifier = selectedMusicSource.bundleIdentifier }
        updatePresentationState(isPlaying: playing)
        if let artwork = snapshot.artwork { visualizerColors = ArtworkPalette.colors(from: artwork) }
        if trackChanged {
            likedOverrideUntil = nil
            lastUpcomingRefresh = .distantPast
            refreshUpcomingTrack()
            refreshLikeState(force: true)
        }
    }

    func resolvedElapsed(_ remote: Double, playing: Bool) -> Double {
        guard remote.isFinite, remote >= 0 else { return nowPlaying.elapsed }
        if Date() < ignoreRemoteElapsedUntil { return nowPlaying.elapsed }
        // Some players publish a stale elapsed value between regular updates.
        // While playing, the local clock must never jump backwards.
        if playing { return max(nowPlaying.elapsed, remote) }
        return remote
    }

    func elapsedForChangedTrack(_ remote: Double) -> Double {
        guard manualTrackChangePending else {
            ignoreRemoteElapsedUntil = .distantPast
            return max(0, remote)
        }
        manualTrackChangePending = false
        ignoreRemoteElapsedUntil = Date().addingTimeInterval(MusicStoreTiming.manualTrackIgnoreElapsedInterval)
        return remote <= 3 ? max(0, remote) : 0
    }

    func updatePresentationState(isPlaying: Bool) {
        if musicPresentationActive != isPlaying { musicPresentationActive = isPlaying }
        if compactPlaybackActive != isPlaying { compactPlaybackActive = isPlaying }
        updatePlaybackClockTimer()
    }

    @discardableResult
    func beginPlaybackTransition(to expected: Bool) -> Int {
        playbackCommandGeneration += 1
        expectedPlaybackState = expected
        playbackOverrideUntil = Date().addingTimeInterval(MusicStoreTiming.playbackOverrideDuration)
        applyPlaybackState(expected, respectingOverride: false)
        return playbackCommandGeneration
    }

    func cancelPlaybackTransition(generation: Int, restoring state: Bool) {
        guard playbackCommandGeneration == generation else { return }
        expectedPlaybackState = nil
        playbackOverrideUntil = .distantPast
        applyPlaybackState(state, respectingOverride: false)
    }

    func applyPlaybackState(_ remoteState: Bool, respectingOverride: Bool = true) {
        let playing = respectingOverride ? resolvedPlaybackState(remoteState) : remoteState
        if nowPlaying.isPlaying != playing { nowPlaying.isPlaying = playing }
        updatePresentationState(isPlaying: playing)
    }

    func resolvedPlaybackState(_ remoteState: Bool) -> Bool {
        guard let expectedPlaybackState else { return remoteState }
        guard Date() < playbackOverrideUntil else {
            self.expectedPlaybackState = nil
            playbackOverrideUntil = .distantPast
            return remoteState
        }
        return expectedPlaybackState
    }

    // MARK: - Async command executor

    /// Универсальный хелпер для выполнения адаптерных команд на background-очереди.
    /// Гарантирует, что коллбэк `onMain` вызывается только если источник и текущий
    /// трек не изменились за время выполнения команды.
    func executeAdapterCommand<T>(
        adapter: any MusicPlayerAdapter,
        context: MusicCommandContext,
        qos: DispatchQoS.QoSClass = .userInitiated,
        requiresSameTrack: Bool = true,
        command: @escaping (any MusicPlayerAdapter, MusicCommandContext) -> T,
        onMain: @escaping (T) -> Void
    ) {
        let source = selectedMusicSource
        let identity = currentTrackIdentity
        DispatchQueue.global(qos: qos).async { [weak self] in
            guard let self else { return }
            let result = command(adapter, context)
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.selectedMusicSource == source,
                      (!requiresSameTrack || self.currentTrackIdentity == identity)
                else { return }
                onMain(result)
            }
        }
    }

}
