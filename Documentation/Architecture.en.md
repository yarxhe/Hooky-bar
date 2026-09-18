# Hooky bar architecture

[Русский](Architecture.md) · [English](Architecture.en.md)

This document describes the architecture of the current application. Planned public APIs are covered by the [SDK plan](SDK-Plan.en.md).

## Layers

```text
┌─────────────────────────────────────────────────────┐
│ SwiftUI Views                                       │
│ MusicPane · ClipboardPane · ToolsPane · Developer   │
└───────────────────────┬─────────────────────────────┘
                        │ user intents
┌───────────────────────▼─────────────────────────────┐
│ Stores                                              │
│ MusicStore · ClipboardStore · NotesStore · ToolsStore│
│ SystemFeatureStore · IntegrationDiagnosticsStore    │
│ InterfaceModel                                      │
└───────────────────────┬─────────────────────────────┘
                        │ internal contracts
┌───────────────────────▼─────────────────────────────┐
│ Adapters                                            │
│ Music · Clipboard · Notes · Tools · System adapters │
└───────────────────────┬─────────────────────────────┘
                        │ system APIs / IPC
┌───────────────────────▼─────────────────────────────┐
│ macOS · Yandex Music · Apple Music · Spotify · gh   │
└─────────────────────────────────────────────────────┘
```

### Views

SwiftUI views read published state and invoke store methods. They must not:

- execute AppleScript;
- read `NSPasteboard`;
- launch processes;
- access CDP, Accessibility, EventKit, or IOBluetooth;
- choose a fallback between external APIs.

### Stores

A store is the sole owner of state for a feature. It:

- selects an appropriate adapter;
- manages observation lifecycle;
- merges data from multiple sources;
- updates state only on the main queue;
- performs optimistic updates followed by reconciliation when an external command is not acknowledged immediately;
- avoids details of a concrete external application when they can remain inside its adapter.

### Adapters

An adapter hides the integration mechanism: AppleScript, MediaRemote, CDP, Accessibility, a file watcher, `gh`, or a system URL. An external service can change without requiring a rewrite of the UI or the main store.

## Application composition

Root dependencies are created in `AppDelegate`:

- `MusicStore`;
- `ClipboardStore`;
- `NotesStore`;
- `ToolsStore`;
- `VolumeStore`;
- `SystemFeatureStore`;
- `IntegrationDiagnosticsStore`;
- `InterfaceModel`;
- `AppLocalization`.

They live for the lifetime of the application process. Monitoring starts in `applicationDidFinishLaunching` and stops in `applicationWillTerminate`.

## Localization

`AppLocalization` stores the `system`, `russian`, or `english` selection. `system` follows the macOS language: Russian system locales use Russian and all other locales use English. User-facing strings go through `L10n`, so SwiftUI, AppKit menus, system events, and adapters share one language and can switch without restarting.

Strings used by a music adapter to locate controls in an external application are not Hooky bar translations. They remain inside the concrete adapter and must not depend on the language selected for Hooky bar.

## Data flow

### User command

```text
Button
  → Store method
  → capability check
  → selected adapter
  → external command
  → refresh / acknowledgement
  → @Published state
  → View update
```

Music commands also keep a temporary expected state. This prevents stale player responses from flipping play/pause several times before the command is acknowledged.

### Source event

```text
External source
  → Adapter callback
  → Store normalization / merge
  → @Published state on main queue
  → View update
```

The clipboard follows this flow: every source publishes a full snapshot of its items and, when available, a separate newly inserted item.

`ClipboardRetentionPolicy` bounds the shared history to 48 unpinned items and 24 hours. Pinned items do not count toward the limit. Automatic and manual cleanup pass items to their source adapters in one batch operation; the system clipboard and original screenshot files are never deleted.

## State and identity

- Adapter identifiers must remain stable between launches.
- Item identifiers must be unique within a source.
- State snapshots must be values rather than references to UI objects.
- An adapter must not mutate SwiftUI state directly.
- A store must discard a late response if the user has already selected another source.

Track identity is currently derived from normalized title and artist. When identity changes, elapsed time, temporary rating state, and the upcoming-track cache are reset.

## Concurrency and performance

- UI and `@Published` state are updated on `DispatchQueue.main`.
- AppleScript, CDP, Git, and `gh` run away from the main queue.
- Polling must be rate-limited and stop with its store.
- Observers must be idempotent: repeated `start` calls must not create another watcher or timer.
- Adapter callbacks must not strongly retain their store.
- Every asynchronous callback is tied to a lifecycle generation: a reply from an old source or stopped session is discarded and cannot release a newer request gate.
- A file `DispatchSource` closes the descriptor captured when that source was created, rather than a shared mutable field, so a late cancellation cannot close a restarted watcher.
- Event-driven system APIs are preferred over idle polling.

## Integration diagnostics

`IntegrationDiagnosticsStore` builds one status snapshot for music, notes, system features, and developer tools through `IntegrationDiagnosticsAdapter`. Potentially slow CDP, GitHub CLI, and system-permission checks run away from the main queue; a late result from an outdated refresh is discarded.

Diagnostics only read existing state and never trigger a system permission prompt. macOS Settings opens only after an explicit user action. macOS does not expose a reliable non-invasive Automation authorization check before first use, so that permission is reported as “checked on use.”

A separate pure builder creates the diagnostics report, which is copied through the adapter only after the user presses the button. The report contains the app version, macOS version, and integration states; paths, clipboard contents, and media metadata are excluded.

The `controls`, `yandex-bridge`, and `memory` operational logs do not contain track names either. They are disabled by default and controlled by the `debugLogging` key in `~/Library/Application Support/Hooky bar/config.json`. The configuration is reloaded while the app is running, so toggling it does not require a restart.

The periodic `memory` heartbeat includes physical footprint and interval-average process CPU (`cpu_percent`, `cpu_interval_s`), without enumerating threads or adding a frequent timer. CPU is the delta of process user/system time; 100% represents one core. The first reading establishes a baseline.

HookyStick was removed on September 15, 2026: its store, windows, subscriptions, list, settings and heartbeat counter are no longer created. Legacy `stickyNotes.*` preferences are neither cleared nor read. Standard note-app integrations through `NotesStore` remain available.

Dev refreshes Git/GitHub on appearance, not on a repeating timer. Repeated appearances use a 15-second cache and coalesce a pending check for the same project. Manual refresh bypasses the cache (but does not duplicate an active request). Choosing another project starts a new refresh; stale results cannot replace it. Horizontal scroll locking respects the clip view's native constrained origin, avoids rewriting scroll settings every frame, and guards against recursive notifications.

## Panel geometry

`InterfaceModel` manages transitions, while `HookySurfaceLayout` is the single geometry source for both SwiftUI and AppKit hit testing. An integration must not resize the `NSPanel` itself. It sends an event or state to the host, and the host selects an existing surface mode.

Current modes:

- `idle`;
- `compact`;
- `systemEvent`;
- `screenshotSuccess`;
- `expanded`;
- `screenshotPreview`.

This constraint is especially important for the SDK: extensions must not introduce incompatible island geometry.

### Native outer-shell animation

`NativeSurface` keeps a 440 × 314 AppKit content host. Expansion, collapse, asymmetric wings, and screenshot modes animate a `CAShapeLayer` mask instead of resizing the entire SwiftUI tree every frame. The contour has matching path topology in every mode; rapid reversals start from the current presentation path. There is no shell timer or content snapshot. Reduce Motion disables spatial animation while retaining short fades.

Geometry comes from `HookySurfaceLayout`; hover and hit testing exclude transparent margins. AppKit hit-test points are converted from superview to local coordinates. Pointer exit schedules collapse even after opening through global hover. The global monitor runs only while the panel is collapsed and coalesces input to at most 30 hit tests per second; an open panel uses its own `NSTrackingArea`. `refreshPanelRendering` only invalidates layout/display, without synchronous repeated drawing. Tests cover fixed content size, rapid transitions, Reduce Motion, coordinates, and lifetime of the actual representable. Measurements and limitations are recorded in the [September 15 report](Native-Surface-Performance-2026-09-15.md) (Russian).

### Native tab transitions

`NativePaneTransition` hosts page contents in AppKit `NSHostingView` instances. Core Animation (`CASpringAnimation` / `CABasicAnimation`) animates their layer translation and opacity outside the page's SwiftUI layout transaction. The outer panel geometry, control animations, and moving color background remain in place. This replaces only the page transition; it is not a full AppKit rewrite or an inherent guarantee of low CPU usage.

At most two pages are attached: current and outgoing. The outgoing page immediately leaves hit testing and Accessibility, then detaches. `NativePaneCache` reuses visited pages only (at most four total hosts), without screenshot snapshots. Detached pages are released eight seconds after collapse, or on memory pressure. There is no recursive forced layout inside `updateNSView`; expanded content gets its final size before the outer shell animation. The independent SwiftUI root receives the environment, including localization. Reduce Motion uses a short fade. Tests cover lifetime, rapid switching, retained page state, eviction, and collapse of the actual representable.

The musical background keeps palette interpolation and motion. `NativeLightRibbons` prepares gradient layers on size/color changes; Core Animation moves rasterized layers without a per-frame `TimelineView`/`Canvas`. Motion stops on detachment, hiding, and Reduce Motion. Retina scale is handled separately. This reduces app-side work, but does not eliminate system compositor cost.

### Dark material instead of Liquid Glass

Since September 13, controls and cards use `HookyMaterialBackground`: system `.ultraThinMaterial` in a dark color scheme with neutral shading. Glass highlights, refraction, outlines, `GlassEffectContainer`, and forced identity changes through glass revision are removed. Reduce Transparency selects an opaque dark fill. The decoration neither intercepts clicks nor changes control geometry; page and panel animations remain enabled. This is a visual change, not a claim that every source of CPU load is fixed.

### Adaptive mini-player

Whenever compact content exists, `MenuBarCollisionDetector` reads the active application's menu-bar bounds on both sides of the notch through Accessibility. `AppDelegate` recomputes the safe width of the leading artwork wing and trailing visualizer wing every 1.2 seconds, and again immediately before the full panel collapses into compact mode. The notch remains centered while each wing spring-shrinks and fades independently. If Accessibility is unavailable, both wings retain their normal width: this is an enhancement, not a player requirement.

## Yandex Music local channel

Hooky is a client of Yandex's internal DevTools endpoint, not a separate web server. `CDPLocalRequest` uses `NWConnection` and system `NWProtocolWebSocket`, with a short connection per request, weak callbacks, and cancellation on success, error, or timeout. At most two operations run concurrently (command/background), with one cached page URL; there is no reply history, cookie/cache store, or `URLSession` pool. System media reading is unchanged.

Port ownership verification remains: expected app executable, `127.0.0.1`, matching port and `/devtools/page/` path. Negative ownership/discovery checks back off for three seconds; explicit commands bypass the negative cache. WebSocket replies are limited to 512 KiB and 32 messages before the matching id. HTTP discovery enforces 16 KiB headers and 1 MiB body while reading; redirects, compression and transfer encodings are rejected. Late replies are discarded. Regression tests use a synthetic loopback server, never the user's music. See the [CPU/CDP report](CPU-CDP-Fixes-2026-09-14.md) (Russian).

## Current module boundaries

```text
Sources/HookyBar/
├── App/          composition root and NSPanel
├── Clipboard/    source models, adapters, and store
├── Integration/  external-app and system-access diagnostics
├── Interface/    geometry, theme, and motion
├── Localization/ application language and string resources
├── Models/       shared models of the current executable target
├── Music/        music adapters and orchestration
├── Notes/        note-taking integrations
├── System/       system events and Pomodoro
├── Tools/        general utilities and developer tools
└── Views/        SwiftUI views
```

## Beta gate

The architectural beta gate is complete:

1. Adapter commands return typed results and errors.
2. `MusicAdapterRegistry` is extensible and connects all built-in players through one contract.
3. `NotesAdapterRegistry` is extensible and connects built-in note apps through one contract.
4. Bluetooth, VPN, Calendar, and AirDrop implement the shared `SystemEventAdapter`.
5. Integration permissions are described by machine-readable `IntegrationCapabilityDeclaration` values.
6. Stable contracts have test doubles and regression tests.

Run contract checks with `./Packaging/test.sh`. After a release build, smoke test, and resource measurement, the version can be published as a beta. A public SDK is not required for the beta. The requirements for graduating from a public beta to a stable release are intentionally separate from the architecture gate and are listed in [Beta readiness](Beta-Readiness.en.md).

## Architectural work before the SDK

These tasks begin after the beta has shipped and stabilized:

1. Move value models and protocols from the executable target into public Swift modules.
2. Define host and extension version compatibility.
3. Add isolation, validation, and a safe lifecycle for third-party code.

Only then can the public API be declared stable.
