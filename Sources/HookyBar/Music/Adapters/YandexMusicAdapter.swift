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
        if cdp.startPlaybackIfNeeded() || accessibility.startPlaybackIfNeeded() {
            return .success
        }
        return systemFallback(context) { mediaController.play() }
    }

    func togglePlayback(context: MusicCommandContext) -> MusicAdapterResult {
        if cdp.playPause() || accessibility.playPause() {
            return .success
        }
        return systemFallback(context) { mediaController.togglePlayPause() }
    }

    func nextTrack(context: MusicCommandContext) -> MusicAdapterResult {
        if cdp.nextTrack() || accessibility.nextTrack() {
            return .success
        }
        return systemFallback(context) { mediaController.nextTrack() }
    }

    func previousTrack(context: MusicCommandContext) -> MusicAdapterResult {
        if cdp.previousTrack() || accessibility.previousTrack() {
            return .success
        }
        return systemFallback(context) { mediaController.previousTrack() }
    }

    func seek(to seconds: Double, context: MusicCommandContext) -> MusicAdapterResult {
        if cdp.seek(to: seconds) {
            return .success
        }
        return systemFallback(context) { mediaController.setTime(seconds: seconds) }
    }

    func setLiked(_ desired: Bool, context: MusicCommandContext) -> MusicAdapterResult {
        if cdp.setLiked(desired) || accessibility.setLiked(desired) {
            return .success
        }
        return systemFallback(context) {
            if desired { mediaController.addToWishList() }
            else { mediaController.removeFromWishList() }
        }
    }

    func setDisliked(_ desired: Bool, context: MusicCommandContext) -> MusicAdapterResult {
        if cdp.setDisliked(desired) || accessibility.setDisliked(desired) {
            return .success
        }
        guard desired else { return .failure(.notSupported) }
        return systemFallback(context) { mediaController.banTrack() }
    }

    private func superDirectSnapshot() -> MusicAdapterSnapshot? {
        guard let info = DirectMediaSnapshotReader.read() else { return nil }
        return snapshot(from: info)
    }
}
