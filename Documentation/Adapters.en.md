# Internal adapters

[Русский](Adapters.md) · [English](Adapters.en.md)

Adapters are the only allowed point of direct communication with an external application, system service, or CLI. They are currently internal: protocols are not `public`, and the product is built as an executable target.

## General rules

Every adapter must:

- have a stable identity or an unambiguous set of supported actions;
- declare capabilities when implementations support different features;
- avoid importing SwiftUI unless necessary;
- avoid storing interface state;
- return a normalized domain model;
- handle a missing app, denied permission, or unavailable data safely;
- keep heavy work off the main queue;
- never access another store directly;
- provide safe `start`/`stop` behavior when observing a source.

## Music

Contract: `MusicPlayerAdapter`.

The registry creates one shared `MediaController` and three adapters. `MusicStore` communicates only with the adapter for the selected `MusicSource`.

### Contract models

- `MusicAdapterCapabilities` describes support for like, dislike, seek, and upcoming track.
- `MusicCommandContext` allows the system MediaRemote fallback only when the selected player owns the system media session.
- `MusicAdapterSnapshot` normalizes title, artist, duration, elapsed time, playback, artwork, and rating.
- `MusicRatingState` keeps like and dislike as independent states.

### Capability matrix

| Adapter | Play/pause | Next/previous | Seek | Like | Dislike | Upcoming |
|---|---:|---:|---:|---:|---:|---:|
| Yandex Music | yes | yes | yes | yes | yes | yes |
| Apple Music | yes | yes | yes | yes | no | yes |
| Spotify | yes | yes | yes | yes | no | yes |

`yes` means that the current adapter declares the capability. A command may still return a typed failure when the application is missing, the feature is unavailable, or macOS denies access.

### Fallback strategy

Yandex Music:

```text
CDP → Accessibility → MediaRemote when ownsSystemMedia
```

Apple Music and Spotify:

```text
AppleScript → MediaRemote when ownsSystemMedia
```

A fallback must never target another application's active media session. Every command receives a `MusicCommandContext` to enforce this rule.

### Adding an internal music player

1. Add a `MusicSource` with its bundle identifier.
2. Implement `MusicPlayerAdapter`.
3. Declare capabilities accurately.
4. Register the adapter in `MusicAdapterRegistry`.
5. Normalize duration and elapsed time to seconds.
6. Test launch with the player closed, track changes, stale elapsed values, and process termination.
7. Test denied permissions and the absence of an active system media session.

Minimal internal adapter skeleton:

```swift
final class ExampleMusicAdapter: MusicPlayerAdapter {
    let source = MusicSource.example
    let mediaController: MediaController
    let capabilities = MusicAdapterCapabilities(
        canLike: false,
        canDislike: false,
        canSeek: true,
        canReadUpcomingTrack: false
    )

    init(mediaController: MediaController) {
        self.mediaController = mediaController
    }

    func startPlayback(context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
    func togglePlayback(context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
    func nextTrack(context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
    func previousTrack(context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
    func seek(to seconds: Double, context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
    func setLiked(_ desired: Bool, context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
    func setDisliked(_ desired: Bool, context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
}
```

This example belongs to the current internal target and is not the future SDK API.

## Clipboard

Contract: `ClipboardSourceAdapter`.

```swift
protocol ClipboardSourceAdapter: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var capability: IntegrationCapabilityDeclaration { get }

    func start(receive: @escaping (ClipboardAdapterUpdate) -> Void)
    func stop()
    func copy(_ item: ClipboardItem) -> IntegrationResult
    func remove(_ item: ClipboardItem) -> IntegrationResult
}
```

`ClipboardAdapterUpdate.items` is the complete current snapshot for one source. `insertedItem` is an optional hint about a new item and is used for the instant screenshot preview.

Built-in sources:

- `system.text` watches `NSPasteboard` and stores up to 60 text entries;
- `system.screenshots` watches the configured screenshot directory and stores up to 40 files.

`ClipboardStore`:

- registers sources;
- merges their snapshots;
- sorts items by `createdAt`;
- routes copy/remove back to the source adapter;
- stores pin state independently of adapters.

A source can be registered before or after monitoring starts:

```swift
clipboardStore.register(MyClipboardAdapter())
```

Model requirements:

- `sourceID` matches `adapter.id`;
- `id` remains stable when the same item is published again;
- `kind`, `text`, and `fileURL` are consistent;
- `start` does not create duplicate watchers;
- `stop` releases timers, descriptors, and callbacks.

## Notes

Contract: `NotesAppAdapter`.

```swift
protocol NotesAppAdapter {
    var app: NotesApp { get }
    var isInstalled: Bool { get }
    var capability: IntegrationCapabilityDeclaration { get }
    func openNotes() -> IntegrationResult
    func createNote() -> IntegrationResult
}
```

Apple Notes and Obsidian are built in. `NotesStore` persists the selected application and sends both commands only to that adapter. `NotesAdapterRegistry` allows adapters to be registered or replaced without changing the UI.

## Utilities

Contract: `ToolActionAdapter`.

```swift
protocol ToolActionAdapter {
    var supportedActions: Set<ToolAction> { get }
    var capability: IntegrationCapabilityDeclaration { get }
    func perform(_ action: ToolAction) -> IntegrationResult
}
```

`ToolsStore` selects the first adapter that declares the requested action. Built-in implementations:

- `SystemToolAdapter` for Calendar and Downloads;
- `DeveloperToolAdapter` for workspace selection, Git snapshots, and shortcuts;
- `GitHubToolAdapter` for repository metadata and the latest GitHub Actions state through an authenticated `gh` installation.

The GitHub adapter does not store or request a Hooky bar token. It uses the user's existing `gh` authorization.

## System events

Bluetooth, VPN, Calendar, and AirDrop implement the shared `SystemEventAdapter`. `SystemFeatureStore` works with an adapter registry and does not know the low-level API of a concrete system event.

The contract guarantees:

- a stable `id`;
- a declaration of the required capability or permission;
- `start(receive:)` and `stop()`;
- a normalized `HookySystemEvent` with no UI management;
- a deduplication key;
- no false startup event for an already connected device or active VPN.

## Errors

Internal contracts use `IntegrationResult` and `IntegrationFailure`. The music layer uses specialized `MusicAdapterResult` and `MusicCommandError` types because it must also distinguish ownership of the system media session.

Typed results distinguish at least:

- application not installed;
- application not running;
- permission denied;
- capability unsupported;
- external service unavailable;
- stale data;
- command accepted but not yet acknowledged.

An adapter does not present alerts or mutate UI on its own. It returns a result, while the store or host decides how to present and handle it.

## New internal adapter checklist

- [ ] The UI does not know the concrete integration API.
- [ ] Every command goes through a store or registry.
- [ ] Capabilities match real support.
- [ ] Late responses are ignored after a source change.
- [ ] Heavy work stays off the main queue.
- [ ] `start` and `stop` are idempotent.
- [ ] A denied permission does not cause repeated system prompts.
- [ ] Tokens are not stored implicitly.
- [ ] Identifiers are stable.
- [ ] The project builds without new warnings.
