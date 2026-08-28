import MediaRemoteAdapter

final class AppleMusicAdapter: MusicPlayerAdapter {
    let source = MusicSource.appleMusic
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
        return AppleScriptRunner.bool(#"tell application id "com.apple.Music" to return player state is playing"#)
    }

    func ratingState(context: MusicCommandContext) -> MusicRatingState? {
        guard isRunning() else { return nil }
        let liked = AppleScriptRunner.bool(#"tell application id "com.apple.Music" to return favorited of current track"#)
            ?? AppleScriptRunner.bool(#"tell application id "com.apple.Music" to return loved of current track"#)
        guard let liked else { return nil }
        return MusicRatingState(liked: liked, disliked: false)
    }

    func startPlayback(context: MusicCommandContext) -> MusicAdapterResult {
        if direct(#"tell application id "com.apple.Music" to play"#) {
            return .success
        }
        return systemFallback(context) { mediaController.play() }
    }

    func togglePlayback(context: MusicCommandContext) -> MusicAdapterResult {
        if direct(#"tell application id "com.apple.Music" to playpause"#) {
            return .success
        }
        return systemFallback(context) { mediaController.togglePlayPause() }
    }

    func nextTrack(context: MusicCommandContext) -> MusicAdapterResult {
        if direct(#"tell application id "com.apple.Music" to next track"#) {
            return .success
        }
        return systemFallback(context) { mediaController.nextTrack() }
    }

    func previousTrack(context: MusicCommandContext) -> MusicAdapterResult {
        if direct(#"tell application id "com.apple.Music" to previous track"#) {
            return .success
        }
        return systemFallback(context) { mediaController.previousTrack() }
    }

    func seek(to seconds: Double, context: MusicCommandContext) -> MusicAdapterResult {
        if direct("tell application id \"com.apple.Music\" to set player position to \(seconds)") {
            return .success
        }
        return systemFallback(context) { mediaController.setTime(seconds: seconds) }
    }

    func setLiked(_ desired: Bool, context: MusicCommandContext) -> MusicAdapterResult {
        let literal = desired ? "true" : "false"
        let result = direct("tell application id \"com.apple.Music\" to set favorited of current track to \(literal)")
            || direct("tell application id \"com.apple.Music\" to set loved of current track to \(literal)")
        if result {
            return .success
        }
        return systemFallback(context) {
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
