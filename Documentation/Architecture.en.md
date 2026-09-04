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
- Event-driven system APIs are preferred over idle polling.

## Integration diagnostics

`IntegrationDiagnosticsStore` builds one status snapshot for music, notes, system features, and developer tools through `IntegrationDiagnosticsAdapter`. Potentially slow CDP, GitHub CLI, and system-permission checks run away from the main queue; a late result from an outdated refresh is discarded.

Diagnostics only read existing state and never trigger a system permission prompt. macOS Settings opens only after an explicit user action. macOS does not expose a reliable non-invasive Automation authorization check before first use, so that permission is reported as “checked on use.”

A separate pure builder creates the diagnostics report, which is copied through the adapter only after the user presses the button. The report contains the app version, macOS version, and integration states; paths, clipboard contents, and media metadata are excluded.

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

Run contract checks with `./Packaging/test.sh`. After a release build, smoke test, and resource measurement, the version can be published as a beta. A public SDK is not required for the beta.

## Architectural work before the SDK

These tasks begin after the beta has shipped and stabilized:

1. Move value models and protocols from the executable target into public Swift modules.
2. Define host and extension version compatibility.
3. Add isolation, validation, and a safe lifecycle for third-party code.

Only then can the public API be declared stable.
