import MediaRemoteAdapter

final class SpotifyMusicAdapter: MusicPlayerAdapter {
    let source = MusicSource.spotify
    let mediaController: MediaController
    let capabilities = MusicAdapterCapabilities(
        canLike: true,
        canDislike: false,
        canSeek: true,
        canReadUpcomingTrack: true
    )

    init(mediaController: MediaController) {
        self.mediaController = mediaController
    }

    func playbackState() -> Bool? {
        guard isRunning() else { return nil }
        return AppleScriptRunner.bool(#"tell application id "com.spotify.client" to return player state is playing"#)
    }

    func ratingState(context: MusicCommandContext) -> MusicRatingState? {
        guard context.ownsSystemMedia, let liked = NowPlayingReader.read()?.liked else { return nil }
        return MusicRatingState(liked: liked, disliked: false)
    }

    func startPlayback(context: MusicCommandContext) -> MusicAdapterResult {
        if direct(#"tell application id "com.spotify.client" to play"#) {
            return .success
        }
        return systemFallback(context) { mediaController.play() }
    }

    func togglePlayback(context: MusicCommandContext) -> MusicAdapterResult {
        if direct(#"tell application id "com.spotify.client" to playpause"#) {
            return .success
        }
        return systemFallback(context) { mediaController.togglePlayPause() }
    }

    func nextTrack(context: MusicCommandContext) -> MusicAdapterResult {
        if direct(#"tell application id "com.spotify.client" to next track"#) {
            return .success
        }
        return systemFallback(context) { mediaController.nextTrack() }
    }

    func previousTrack(context: MusicCommandContext) -> MusicAdapterResult {
        if direct(#"tell application id "com.spotify.client" to previous track"#) {
            return .success
        }
        return systemFallback(context) { mediaController.previousTrack() }
    }

    func seek(to seconds: Double, context: MusicCommandContext) -> MusicAdapterResult {
        if direct("tell application id \"com.spotify.client\" to set player position to \(seconds)") {
            return .success
        }
        return systemFallback(context) { mediaController.setTime(seconds: seconds) }
    }

    func setLiked(_ desired: Bool, context: MusicCommandContext) -> MusicAdapterResult {
        systemFallback(context) {
            if desired { mediaController.addToWishList() }
            else { mediaController.removeFromWishList() }
        }
    }

    func setDisliked(_ desired: Bool, context: MusicCommandContext) -> MusicAdapterResult {
        .failure(.notSupported)
    }

    private func direct(_ script: String) -> Bool {
        guard isRunning() else { return false }
        return AppleScriptRunner.command(script)
    }
}
