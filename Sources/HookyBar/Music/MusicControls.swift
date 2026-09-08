import AppKit
import SwiftUI

extension MusicStore {
    func toggleLike() {
        guard activeAdapter.capabilities.canLike else {
            HookyDiagnostics.control("action=like phase=rejected reason=unsupported")
            return
        }
        let startedAt = Date()
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
        HookyDiagnostics.control("action=like phase=request desired=\(desired) source=\(source.rawValue)")
        executeAdapterCommand(
            adapter: adapter,
            context: context,
            command: { $0.setLiked(desired, context: $1) }
        ) { [weak self] result in
            HookyDiagnostics.control(
                "action=like phase=result success=\(result.success) latency_ms=\(Int(Date().timeIntervalSince(startedAt) * 1_000)) error=\(String(describing: result.error))"
            )
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
        guard activeAdapter.capabilities.canDislike else {
            HookyDiagnostics.control("action=dislike phase=rejected reason=unsupported")
            return
        }
        let startedAt = Date()
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
        HookyDiagnostics.control("action=dislike phase=request desired=\(desired) source=\(source.rawValue)")
        executeAdapterCommand(
            adapter: adapter,
            context: context,
            command: { $0.setDisliked(desired, context: $1) }
        ) { [weak self] result in
            HookyDiagnostics.control(
                "action=dislike phase=result success=\(result.success) latency_ms=\(Int(Date().timeIntervalSince(startedAt) * 1_000)) error=\(String(describing: result.error))"
            )
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
        HookyDiagnostics.control("action=select_source source=\(source.rawValue)")
        selectedMusicSource = source
    }

    func openSelectedMusicApp() {
        let adapter = activeAdapter
        let alreadyRunning = adapter.isRunning()
        HookyDiagnostics.control(
            "action=open_player source=\(selectedMusicSource.rawValue) already_running=\(alreadyRunning)"
        )
        if !alreadyRunning { clearSelectedTrack() }
        adapter.launch()
    }

    func togglePlayback() {
        let startedAt = Date()
        controlPulse += 1
        let adapter = activeAdapter
        let appIsActuallyRunning = adapter.isRunning()
        HookyDiagnostics.control(
            "action=playback phase=request source=\(selectedMusicSource.rawValue) app_running=\(appIsActuallyRunning) store_running=\(isSelectedMusicAppRunning) track_known=\(currentTrackIdentity != nil) pending=\(pendingPlaybackStartToken != nil) expected_playing=\(!nowPlaying.isPlaying)"
        )
        if pendingPlaybackStartToken != nil {
            // Повторный клик во время холодного старта не создаёт второй цикл
            // команд. Он только снова активирует выбранный плеер и ускоряет
            // уже существующее намерение воспроизведения.
            openSelectedMusicApp()
            resumePendingPlaybackStart()
            HookyDiagnostics.control("action=playback phase=route route=resume_pending")
            return
        }
        if !appIsActuallyRunning {
            isSelectedMusicAppRunning = false
            openSelectedMusicApp()
            beginPendingPlaybackStart()
            HookyDiagnostics.control("action=playback phase=route route=cold_launch")
            return
        }
        if !isSelectedMusicAppRunning {
            openSelectedMusicApp()
            beginPendingPlaybackStart(initialDelay: MusicStoreTiming.readyPlaybackDelay)
            HookyDiagnostics.control("action=playback phase=route route=refresh_running")
            return
        }
        if currentTrackIdentity == nil {
            beginPendingPlaybackStart(initialDelay: MusicStoreTiming.readyPlaybackDelay)
            HookyDiagnostics.control("action=playback phase=route route=start_without_track")
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
            HookyDiagnostics.control(
                "action=playback phase=result success=\(result.success) latency_ms=\(Int(Date().timeIntervalSince(startedAt) * 1_000)) error=\(String(describing: result.error))"
            )
            guard let self, self.selectedMusicSource == source else { return }
            if !result.success {
                self.cancelPlaybackTransition(generation: generation, restoring: previous)
            }
            self.refreshMediaSnapshot()
        }
    }

    func beginPendingPlaybackStart(
        initialDelay: TimeInterval = MusicStoreTiming.launchPlaybackDelay
    ) {
        cancelPendingPlaybackStart()
        let token = UUID()
        pendingPlaybackStartToken = token
        pendingPlaybackStartDeadline = Date().addingTimeInterval(MusicStoreTiming.launchPlaybackTimeout)
        HookyDiagnostics.control(
            "action=playback phase=pending_begin initial_delay_ms=\(Int(initialDelay * 1_000))"
        )
        schedulePendingPlaybackStart(token: token, delay: initialDelay)
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
            HookyDiagnostics.control("action=playback phase=pending_timeout")
            cancelPendingPlaybackStart()
            return
        }
        pendingPlaybackStartInFlightToken = token
        let startedAt = Date()
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
            HookyDiagnostics.control(
                "action=playback phase=pending_result success=\(result.success) latency_ms=\(Int(Date().timeIntervalSince(startedAt) * 1_000)) error=\(String(describing: result.error))"
            )
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
                        HookyDiagnostics.control("action=playback phase=verified playing=true")
                        self.cancelPendingPlaybackStart()
                    } else {
                        HookyDiagnostics.control("action=playback phase=verified playing=\(String(describing: playing)) retry=true")
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
        ignoreRemoteElapsedUntil = Date().addingTimeInterval(3)
        controlPulse += 1
        performNavigationCommand(action: "previous") { adapter, context in
            adapter.previousTrack(context: context)
        }
    }

    func nextTrack() {
        trackNavigationDirection = 1
        manualTrackChangePending = true
        ignoreRemoteElapsedUntil = Date().addingTimeInterval(3)
        controlPulse += 1
        performNavigationCommand(action: "next") { adapter, context in
            adapter.nextTrack(context: context)
        }
    }

    func performNavigationCommand(
        action: String,
        _ command: @escaping (any MusicPlayerAdapter, MusicCommandContext) -> MusicAdapterResult
    ) {
        let startedAt = Date()
        HookyDiagnostics.control("action=\(action) phase=request source=\(selectedMusicSource.rawValue)")
        navigationCommandGeneration &+= 1
        let generation = navigationCommandGeneration
        let source = selectedMusicSource
        let adapter = activeAdapter
        let context = commandContext
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = command(adapter, context)
            DispatchQueue.main.async {
                HookyDiagnostics.control(
                    "action=\(action) phase=result success=\(result.success) latency_ms=\(Int(Date().timeIntervalSince(startedAt) * 1_000)) error=\(String(describing: result.error))"
                )
                guard let self, self.selectedMusicSource == source,
                      self.navigationCommandGeneration == generation else { return }
                if !result.success {
                    self.finishUnconfirmedNavigation(generation: generation)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + MusicStoreTiming.navigationRefreshDelay) { [weak self] in
                    self?.refreshMediaSnapshot()
                    self?.recoverSelectedPlaybackPresentation()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.finishUnconfirmedNavigation(generation: generation)
                }
            }
        }
    }

    func finishUnconfirmedNavigation(generation: Int) {
        guard navigationCommandGeneration == generation, manualTrackChangePending else { return }
        manualTrackChangePending = false
        ignoreRemoteElapsedUntil = .distantPast
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
            HookyDiagnostics.control("action=seek phase=rejected reason=unavailable")
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
        let startedAt = Date()
        HookyDiagnostics.control("action=seek phase=request source=\(source.rawValue)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = adapter.seek(to: clamped, context: context)
            DispatchQueue.main.async {
                HookyDiagnostics.control(
                    "action=seek phase=result success=\(result.success) latency_ms=\(Int(Date().timeIntervalSince(startedAt) * 1_000)) error=\(String(describing: result.error))"
                )
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
        navigationCommandGeneration &+= 1
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
        visualizerColors = ArtworkPalette.fallback
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
