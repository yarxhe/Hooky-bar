import AppKit
import SwiftUI

extension MusicStore {
    func toggleLike() {
        guard activeAdapter.capabilities.canLike else { return }
        let desired = !nowPlaying.isLiked
        let previous = MusicRatingState(liked: nowPlaying.isLiked, disliked: nowPlaying.isDisliked)
        let source = selectedMusicSource
        let identity = currentTrackIdentity
        let adapter = activeAdapter
        let context = commandContext
        nowPlaying.isLiked = desired
        if desired { nowPlaying.isDisliked = false }
        likedOverrideUntil = Date().addingTimeInterval(MusicStoreTiming.likedOverrideDuration)
        controlPulse += 1
        executeAdapterCommand(
            adapter: adapter,
            context: context,
            command: { $0.setLiked(desired, context: $1) }
        ) { [weak self] result in
            DispatchQueue.main.asyncAfter(deadline: .now() + MusicStoreTiming.likeRecoveryDelay) {
                guard let self,
                      self.selectedMusicSource == source,
                      self.currentTrackIdentity == identity
                else { return }
                if !result.success {
                    self.nowPlaying.isLiked = previous.liked
                    self.nowPlaying.isDisliked = previous.disliked
                }
                self.likedOverrideUntil = nil
                self.refreshLikeState(force: true)
            }
        }
    }

    func toggleDislike() {
        guard activeAdapter.capabilities.canDislike else { return }
        let desired = !nowPlaying.isDisliked
        let previous = MusicRatingState(liked: nowPlaying.isLiked, disliked: nowPlaying.isDisliked)
        let source = selectedMusicSource
        let identity = currentTrackIdentity
        let adapter = activeAdapter
        let context = commandContext
        nowPlaying.isDisliked = desired
        if desired { nowPlaying.isLiked = false }
        likedOverrideUntil = Date().addingTimeInterval(MusicStoreTiming.likedOverrideDuration)
        controlPulse += 1
        executeAdapterCommand(
            adapter: adapter,
            context: context,
            command: { $0.setDisliked(desired, context: $1) }
        ) { [weak self] result in
            DispatchQueue.main.asyncAfter(deadline: .now() + MusicStoreTiming.likeRecoveryDelay) {
                guard let self,
                      self.selectedMusicSource == source,
                      self.currentTrackIdentity == identity
                else { return }
                if !result.success {
                    self.nowPlaying.isLiked = previous.liked
                    self.nowPlaying.isDisliked = previous.disliked
                }
                self.likedOverrideUntil = nil
                self.refreshLikeState(force: true)
            }
        }
    }

    func selectMusicSource(_ source: MusicSource) {
        selectedMusicSource = source
    }

    func openSelectedMusicApp() {
        let adapter = activeAdapter
        let alreadyRunning = adapter.isRunning()
        if !alreadyRunning { clearSelectedTrack() }
        adapter.launch()
    }

    func togglePlayback() {
        controlPulse += 1
        let adapter = activeAdapter
        let appIsActuallyRunning = adapter.isRunning()
        if pendingPlaybackStartToken != nil {
            // Повторный клик во время холодного старта не создаёт второй цикл
            // команд. Он только снова активирует выбранный плеер и ускоряет
            // уже существующее намерение воспроизведения.
            openSelectedMusicApp()
            resumePendingPlaybackStart()
            return
        }
        if !appIsActuallyRunning {
            isSelectedMusicAppRunning = false
            openSelectedMusicApp()
            beginPendingPlaybackStart()
            return
        }
        if !isSelectedMusicAppRunning {
            openSelectedMusicApp()
            beginPendingPlaybackStart()
            return
        }
        if currentTrackIdentity == nil {
            beginPendingPlaybackStart()
            return
        }
        cancelPendingPlaybackStart()
        let source = selectedMusicSource
        let previous = nowPlaying.isPlaying
        let context = commandContext
        let desired = !previous
        let generation = beginPlaybackTransition(to: desired)
        executeAdapterCommand(
            adapter: adapter,
            context: context,
            command: { $0.togglePlayback(context: $1) }
        ) { [weak self] result in
            guard let self, self.selectedMusicSource == source else { return }
            if !result.success {
                self.cancelPlaybackTransition(generation: generation, restoring: previous)
            }
            self.refreshMediaSnapshot()
        }
    }

    func beginPendingPlaybackStart() {
        cancelPendingPlaybackStart()
        let token = UUID()
        pendingPlaybackStartToken = token
        pendingPlaybackStartDeadline = Date().addingTimeInterval(MusicStoreTiming.launchPlaybackTimeout)
        schedulePendingPlaybackStart(token: token, delay: MusicStoreTiming.launchPlaybackDelay)
    }

    func resumePendingPlaybackStart() {
        guard let token = pendingPlaybackStartToken else { return }
        schedulePendingPlaybackStart(token: token, delay: 0.08)
    }

    func schedulePendingPlaybackStart(token: UUID, delay: TimeInterval) {
        guard pendingPlaybackStartToken == token else { return }
        pendingPlaybackStartWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.attemptPendingPlaybackStart(token: token)
        }
        pendingPlaybackStartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func attemptPendingPlaybackStart(token: UUID) {
        guard pendingPlaybackStartToken == token else { return }
        guard pendingPlaybackStartInFlightToken == nil else { return }
        guard Date() < pendingPlaybackStartDeadline else {
            cancelPendingPlaybackStart()
            return
        }
        pendingPlaybackStartInFlightToken = token
        let source = selectedMusicSource
        let adapter = activeAdapter
        refreshMusicState()
        let context = commandContext
        executeAdapterCommand(
            adapter: adapter,
            context: context,
            qos: .userInitiated,
            requiresSameTrack: false,
            command: { $0.startPlayback(context: $1) }
        ) { [weak self] result in
            guard let self else { return }
            if self.pendingPlaybackStartInFlightToken == token {
                self.pendingPlaybackStartInFlightToken = nil
            }
            guard self.selectedMusicSource == source,
                  self.pendingPlaybackStartToken == token else { return }
            if result.success {
                self.verifyPendingPlaybackStart(source: source, adapter: adapter, token: token)
            } else {
                self.refreshMediaSnapshot()
                self.schedulePendingPlaybackStart(
                    token: token,
                    delay: MusicStoreTiming.retryPlaybackDelay
                )
            }
        }
    }

    func verifyPendingPlaybackStart(
        source: MusicSource,
        adapter: any MusicPlayerAdapter,
        token: UUID
    ) {
        refreshMediaSnapshot()
        DispatchQueue.main.asyncAfter(deadline: .now() + MusicStoreTiming.postCommandSnapshotDelay) { [weak self] in
            guard let self,
                  self.selectedMusicSource == source,
                  self.pendingPlaybackStartToken == token else { return }
            let context = self.commandContext
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let snapshot = adapter.directSnapshot(context: context)
                let playing = snapshot?.isPlaying ?? adapter.playbackState()
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.selectedMusicSource == source,
                          self.pendingPlaybackStartToken == token else { return }
                    self.refreshMusicState()
                    self.refreshMediaSnapshot()
                    if let snapshot { self.applyAdapterSnapshot(snapshot, marksSystemOwnership: false) }
                    if playing == true {
                        self.cancelPendingPlaybackStart()
                    } else {
                        self.schedulePendingPlaybackStart(
                            token: token,
                            delay: MusicStoreTiming.retryPlaybackDelay
                        )
                    }
                }
            }
        }
    }

    func cancelPendingPlaybackStart() {
        pendingPlaybackStartWorkItem?.cancel()
        pendingPlaybackStartWorkItem = nil
        pendingPlaybackStartToken = nil
        pendingPlaybackStartInFlightToken = nil
        pendingPlaybackStartDeadline = .distantPast
    }

    func previousTrack() {
        trackNavigationDirection = -1
        manualTrackChangePending = true
        ignoreRemoteElapsedUntil = .distantFuture
        nowPlaying.elapsed = 0
        controlPulse += 1
        performNavigationCommand { adapter, context in adapter.previousTrack(context: context) }
    }

    func nextTrack() {
        trackNavigationDirection = 1
        manualTrackChangePending = true
        ignoreRemoteElapsedUntil = .distantFuture
        nowPlaying.elapsed = 0
        controlPulse += 1
        performNavigationCommand { adapter, context in adapter.nextTrack(context: context) }
    }

    func performNavigationCommand(
        _ command: @escaping (any MusicPlayerAdapter, MusicCommandContext) -> MusicAdapterResult
    ) {
        let source = selectedMusicSource
        let adapter = activeAdapter
        let context = commandContext
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = command(adapter, context)
            DispatchQueue.main.async {
                guard let self, self.selectedMusicSource == source else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + MusicStoreTiming.navigationRefreshDelay) { [weak self] in
                    self?.refreshMediaSnapshot()
                    self?.recoverSelectedPlaybackPresentation()
                }
            }
        }
    }

    func seek(to destination: Double) {
        finishScrubbing(at: destination)
    }

    func beginScrubbing() {
        isScrubbingPlayback = true
        ignoreRemoteElapsedUntil = .distantFuture
    }

    func previewScrubbing(at destination: Double) {
        guard isSelectedMusicAppRunning, activeAdapter.capabilities.canSeek else { return }
        let clamped = clampedSeekDestination(destination)
        nowPlaying.elapsed = clamped
    }

    func finishScrubbing(at destination: Double) {
        guard isSelectedMusicAppRunning, activeAdapter.capabilities.canSeek else {
            isScrubbingPlayback = false
            ignoreRemoteElapsedUntil = .distantPast
            return
        }
        let clamped = clampedSeekDestination(destination)
        isScrubbingPlayback = false
        ignoreRemoteElapsedUntil = Date().addingTimeInterval(MusicStoreTiming.recoveryThrottleInterval)
        nowPlaying.elapsed = clamped
        let source = selectedMusicSource
        let adapter = activeAdapter
        let context = commandContext
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = adapter.seek(to: clamped, context: context)
            DispatchQueue.main.async {
                guard let self, self.selectedMusicSource == source else { return }
                if !result.success { self.ignoreRemoteElapsedUntil = .distantPast }
                self.refreshMediaSnapshot()
            }
        }
    }

    func clampedSeekDestination(_ destination: Double) -> Double {
        let upperBound = nowPlaying.duration > 0 ? nowPlaying.duration : max(0, destination)
        return min(max(0, destination), upperBound)
    }

    func clearSelectedTrack() {
        activeMediaBundleIdentifier = nil
        adapterHasProvidedTrack = false
        upcomingTrack = nil
        isScrubbingPlayback = false
        manualTrackChangePending = false
        ignoreRemoteElapsedUntil = .distantPast
        currentTrackIdentity = nil
        expectedPlaybackState = nil
        playbackOverrideUntil = .distantPast
        playbackCommandGeneration += 1
        nowPlaying = NowPlayingSnapshot(artist: selectedMusicSource.fullTitle)
        trackPresentationRevision &+= 1
        artworkPresentationRevision &+= 1
        if musicPresentationActive { musicPresentationActive = false }
        if compactPlaybackActive { compactPlaybackActive = false }
    }

    var selectedSourceOwnsSystemMedia: Bool {
        activeMediaBundleIdentifier == selectedMusicSource.bundleIdentifier
    }

    var canDislike: Bool { activeAdapter.capabilities.canDislike }

}
