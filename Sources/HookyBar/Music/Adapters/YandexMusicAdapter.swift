import AppKit
import ApplicationServices
import MediaRemoteAdapter

final class YandexMusicAdapter: MusicPlayerAdapter {
    let source = MusicSource.yandex
    let mediaController: MediaController
    let capabilities = MusicAdapterCapabilities(
        canLike: true,
        canDislike: true,
        canSeek: true,
        canReadUpcomingTrack: true
    )

    private let cdp: YandexCDPBridge
    private let accessibility = YandexMusicBridge()

    init(mediaController: MediaController) {
        self.mediaController = mediaController
        cdp = YandexCDPBridge(
            port: YandexCDPBridge.persistedRandomPort(),
            expectedBundleIdentifier: MusicSource.yandex.bundleIdentifier
        )
    }

    func launch() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if !isRunning() {
            configuration.arguments = [
                "--remote-debugging-address=127.0.0.1",
                "--remote-debugging-port=\(cdp.port)"
            ]
        }
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    func directSnapshot(context: MusicCommandContext) -> MusicAdapterSnapshot? {
        if context.ownsSystemMedia, let systemSnapshot = superDirectSnapshot() {
            return systemSnapshot
        }
        return cdp.currentSnapshot()
    }

    func playbackState() -> Bool? {
        cdp.playbackState() ?? accessibility.playbackState()
    }

    func controlChannelAvailable() -> Bool? {
        guard isRunning() else { return false }
        return cdp.isAvailable() || AXIsProcessTrusted()
    }

    func ratingState(context: MusicCommandContext) -> MusicRatingState? {
        let state = cdp.ratingState() ?? accessibility.ratingState()
        return state.map { MusicRatingState(liked: $0.liked, disliked: $0.disliked) }
    }

    func upcomingTrack(context: MusicCommandContext) -> UpcomingTrack? {
        cdp.nextTrackInfo()
            ?? accessibility.nextTrackInfo()
            ?? (context.ownsSystemMedia ? PlaybackQueueReader.readNext() : nil)
    }

    func startPlayback(context: MusicCommandContext) -> MusicAdapterResult {
        let startedAt = Date()
        if cdp.startPlaybackIfNeeded() { return logged(.success, action: "start", channel: "cdp", since: startedAt) }
        if accessibility.startPlaybackIfNeeded() { return logged(.success, action: "start", channel: "accessibility", since: startedAt) }
        return logged(
            currentPlayerSystemFallback(context) { mediaController.play() },
            action: "start", channel: "media_remote", since: startedAt
        )
    }

    func togglePlayback(context: MusicCommandContext) -> MusicAdapterResult {
        let startedAt = Date()
        if cdp.playPause() { return logged(.success, action: "toggle", channel: "cdp", since: startedAt) }
        if accessibility.playPause() { return logged(.success, action: "toggle", channel: "accessibility", since: startedAt) }
        return logged(
            currentPlayerSystemFallback(context) { mediaController.togglePlayPause() },
            action: "toggle", channel: "media_remote", since: startedAt
        )
    }

    func nextTrack(context: MusicCommandContext) -> MusicAdapterResult {
        let startedAt = Date()
        if cdp.nextTrack() { return logged(.success, action: "next", channel: "cdp", since: startedAt) }
        if accessibility.nextTrack() { return logged(.success, action: "next", channel: "accessibility", since: startedAt) }
        return logged(
            currentPlayerSystemFallback(context) { mediaController.nextTrack() },
            action: "next", channel: "media_remote", since: startedAt
        )
    }

    func previousTrack(context: MusicCommandContext) -> MusicAdapterResult {
        let startedAt = Date()
        if cdp.previousTrack() { return logged(.success, action: "previous", channel: "cdp", since: startedAt) }
        if accessibility.previousTrack() { return logged(.success, action: "previous", channel: "accessibility", since: startedAt) }
        return logged(
            currentPlayerSystemFallback(context) { mediaController.previousTrack() },
            action: "previous", channel: "media_remote", since: startedAt
        )
    }

    func seek(to seconds: Double, context: MusicCommandContext) -> MusicAdapterResult {
        let startedAt = Date()
        if cdp.seek(to: seconds) {
            return logged(.success, action: "seek", channel: "cdp", since: startedAt)
        }
        return logged(
            currentPlayerSystemFallback(context) { mediaController.setTime(seconds: seconds) },
            action: "seek", channel: "media_remote", since: startedAt
        )
    }

    func setLiked(_ desired: Bool, context: MusicCommandContext) -> MusicAdapterResult {
        let startedAt = Date()
        if cdp.setLiked(desired) { return logged(.success, action: "like", channel: "cdp", since: startedAt) }
        if accessibility.setLiked(desired) { return logged(.success, action: "like", channel: "accessibility", since: startedAt) }
        let result = currentPlayerSystemFallback(context) {
            if desired { mediaController.addToWishList() }
            else { mediaController.removeFromWishList() }
        }
        return logged(result, action: "like", channel: "media_remote", since: startedAt)
    }

    func setDisliked(_ desired: Bool, context: MusicCommandContext) -> MusicAdapterResult {
        let startedAt = Date()
        if cdp.setDisliked(desired) { return logged(.success, action: "dislike", channel: "cdp", since: startedAt) }
        if accessibility.setDisliked(desired) { return logged(.success, action: "dislike", channel: "accessibility", since: startedAt) }
        guard desired else {
            return logged(.failure(.notSupported), action: "dislike", channel: "none", since: startedAt)
        }
        return logged(
            currentPlayerSystemFallback(context) { mediaController.banTrack() },
            action: "dislike", channel: "media_remote", since: startedAt
        )
    }

    private func logged(
        _ result: MusicAdapterResult,
        action: String,
        channel: String,
        since startedAt: Date
    ) -> MusicAdapterResult {
        HookyDiagnostics.control(
            "adapter=yandex action=\(action) channel=\(channel) success=\(result.success) latency_ms=\(Int(Date().timeIntervalSince(startedAt) * 1_000)) error=\(String(describing: result.error))"
        )
        return result
    }

    /// The store's ownership flag is updated asynchronously by MediaRemote and
    /// can briefly be stale after Yandex changes playback state. Re-read the
    /// current system snapshot before rejecting a fallback command, while still
    /// refusing to control a different media application.
    private func currentPlayerSystemFallback(
        _ context: MusicCommandContext,
        _ command: () -> Void
    ) -> MusicAdapterResult {
        guard context.ownsSystemMedia || superDirectSnapshot() != nil else {
            return .failure(.systemMediaNotOwned)
        }
        command()
        return .success
    }

    private func superDirectSnapshot() -> MusicAdapterSnapshot? {
        guard let info = DirectMediaSnapshotReader.read() else { return nil }
        return snapshot(from: info)
    }
}
