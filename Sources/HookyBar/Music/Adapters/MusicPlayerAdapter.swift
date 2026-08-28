import AppKit
import MediaRemoteAdapter

struct MusicAdapterCapabilities: Equatable {
    let canLike: Bool
    let canDislike: Bool
    let canSeek: Bool
    let canReadUpcomingTrack: Bool
}

struct MusicCommandContext {
    let ownsSystemMedia: Bool
}

struct MusicRatingState: Equatable {
    let liked: Bool
    let disliked: Bool
}

struct MusicAdapterSnapshot {
    let title: String
    let artist: String
    let duration: Double
    let elapsed: Double
    let isPlaying: Bool
    let artwork: NSImage?
    let rating: MusicRatingState?

    var identity: String {
        "\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }
}

enum MusicCommandError: Error, Sendable {
    case adapterUnavailable
    case systemMediaNotOwned
    case commandFailed
    case notSupported
}

struct MusicAdapterResult {
    let success: Bool
    let error: MusicCommandError?
}

extension MusicAdapterResult {
    static let success = MusicAdapterResult(success: true, error: nil)
    static func failure(_ error: MusicCommandError) -> MusicAdapterResult {
        MusicAdapterResult(success: false, error: error)
    }
}

protocol MusicPlayerAdapter: AnyObject {
    var source: MusicSource { get }
    var mediaController: MediaController { get }
    var capabilities: MusicAdapterCapabilities { get }
    var integrationCapability: IntegrationCapabilityDeclaration { get }

    func isRunning() -> Bool
    func launch()
    func snapshot(from info: TrackInfo) -> MusicAdapterSnapshot?
    func directSnapshot(context: MusicCommandContext) -> MusicAdapterSnapshot?
    func playbackState() -> Bool?
    func ratingState(context: MusicCommandContext) -> MusicRatingState?
    func upcomingTrack(context: MusicCommandContext) -> UpcomingTrack?

    @discardableResult func startPlayback(context: MusicCommandContext) -> MusicAdapterResult
    @discardableResult func togglePlayback(context: MusicCommandContext) -> MusicAdapterResult
    @discardableResult func nextTrack(context: MusicCommandContext) -> MusicAdapterResult
    @discardableResult func previousTrack(context: MusicCommandContext) -> MusicAdapterResult
    @discardableResult func seek(to seconds: Double, context: MusicCommandContext) -> MusicAdapterResult
    @discardableResult func setLiked(_ desired: Bool, context: MusicCommandContext) -> MusicAdapterResult
    @discardableResult func setDisliked(_ desired: Bool, context: MusicCommandContext) -> MusicAdapterResult
}

extension MusicPlayerAdapter {
    var bundleIdentifier: String { source.bundleIdentifier }

    var integrationCapability: IntegrationCapabilityDeclaration {
        switch source {
        case .yandex:
            return IntegrationCapabilityDeclaration(
                id: "music.yandex",
                permissions: [.accessibility, .localNetwork]
            )
        case .appleMusic:
            return IntegrationCapabilityDeclaration(id: "music.apple", permissions: [.automation])
        case .spotify:
            return IntegrationCapabilityDeclaration(id: "music.spotify", permissions: [.automation])
        }
    }

    func isRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier && !$0.isTerminated
        }
    }

    func launch() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    func snapshot(from info: TrackInfo) -> MusicAdapterSnapshot? {
        let payload = info.payload
        guard payload.bundleIdentifier == bundleIdentifier,
              let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        let duration = max(0, (payload.durationMicros ?? 0) / 1_000_000)
        let elapsed = max(0, payload.currentElapsedTime ?? ((payload.elapsedTimeMicros ?? 0) / 1_000_000))
        return MusicAdapterSnapshot(
            title: title,
            artist: payload.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            duration: duration,
            elapsed: duration > 0 ? min(elapsed, duration) : elapsed,
            isPlaying: payload.isPlaying ?? ((payload.playbackRate ?? 0) > 0),
            artwork: payload.artwork,
            rating: nil
        )
    }

    func directSnapshot(context: MusicCommandContext) -> MusicAdapterSnapshot? {
        guard context.ownsSystemMedia, let info = DirectMediaSnapshotReader.read() else { return nil }
        return snapshot(from: info)
    }

    func playbackState() -> Bool? { nil }
    func ratingState(context: MusicCommandContext) -> MusicRatingState? { nil }

    func upcomingTrack(context: MusicCommandContext) -> UpcomingTrack? {
        guard context.ownsSystemMedia else { return nil }
        return PlaybackQueueReader.readNext()
    }

    func systemFallback(_ context: MusicCommandContext, _ command: () -> Void) -> MusicAdapterResult {
        guard context.ownsSystemMedia else { return .failure(.systemMediaNotOwned) }
        command()
        return .success
    }
}

final class MusicAdapterRegistry {
    private let mediaController = MediaController()
    private var adapters: [MusicSource: any MusicPlayerAdapter] = [:]

    init(additionalAdapters: [any MusicPlayerAdapter] = []) {
        [
            YandexMusicAdapter(mediaController: mediaController),
            AppleMusicAdapter(mediaController: mediaController),
            SpotifyMusicAdapter(mediaController: mediaController)
        ].forEach(register)
        additionalAdapters.forEach(register)
    }

    func register(_ adapter: any MusicPlayerAdapter) {
        adapters[adapter.source] = adapter
    }

    func adapter(for source: MusicSource) -> any MusicPlayerAdapter {
        guard let adapter = adapters[source] else {
            preconditionFailure("Music adapter is not registered for \(source.rawValue)")
        }
        return adapter
    }

    var registeredSources: [MusicSource] {
        MusicSource.allCases.filter { adapters[$0] != nil }
    }

    var integrationCapabilities: [IntegrationCapabilityDeclaration] {
        registeredSources
            .compactMap { adapters[$0]?.integrationCapability }
            .sorted { $0.id < $1.id }
    }

    func startListening(onTrackInfo: @escaping (TrackInfo?) -> Void) {
        mediaController.onTrackInfoReceived = onTrackInfo
        mediaController.startListening()
    }

    func stopListening() {
        mediaController.stopListening()
    }

    func requestSystemSnapshot(_ completion: @escaping (TrackInfo?) -> Void) {
        mediaController.getTrackInfo(completion)
    }
}
