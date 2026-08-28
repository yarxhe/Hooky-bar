# HookyBar SDK plan

[Русский](SDK-Plan.md) · [English](SDK-Plan.en.md)

There is no public SDK yet. This document records the direction and boundaries of the first version, but does not promise stability for the proposed type names.

## Why an SDK

The SDK should allow an integration to be added without importing internal stores or modifying the main executable target. Hooky bar must retain control over:

- island geometry;
- opening and closing motion;
- event queueing;
- permissions;
- lifecycle;
- performance;
- consistent visual style.

## Non-goals for the first version

An extension must not:

- receive arbitrary access to `MusicStore`, `ClipboardStore`, or `InterfaceModel`;
- resize the `NSPanel`;
- render a completely arbitrary SwiftUI window inside the island;
- read unrelated user data without a capability;
- load unsigned executable code without validation;
- bypass the host and directly control other extensions.

## Proposed modules

```text
HookyBarCore       value models, IDs, capabilities, errors
HookyBarSDK        public protocols and host context
HookyBarHost       registry, lifecycle, permissions, event queue
HookyBar           application and built-in adapters
```

Built-in adapters should use the same public contract as third-party adapters. Otherwise the SDK will quickly diverge from the behavior of the application itself.

## First extension types

Priority minimum:

1. **Tool action** — a command presented with a standard card or button.
2. **Compact event** — a short system notification using existing mini-player geometry.
3. **Clipboard source** — a provider of text, files, or images.
4. **Settings section** — typed settings rendered with standard controls.

Music player adapters should become public only after typed errors and state acknowledgement are stable, because this contract is more complex than a regular command.

## Manifest

The proposed manifest is declarative:

```json
{
  "identifier": "dev.example.hooky.github",
  "name": "GitHub Status",
  "version": "0.1.0",
  "minimumHostVersion": "0.2.0",
  "entryPoint": "GitHubExtension",
  "capabilities": ["network", "openURL"],
  "contributions": ["tool", "compactEvent"]
}
```

Exact keys will be finalized after the extension delivery model is selected.

## Lifecycle

```text
discover
  → validate manifest and compatibility
  → ask/verify capabilities
  → instantiate
  → start(context)
  → receive actions / publish snapshots
  → stop()
  → release
```

A repeated `start` is not allowed without `stop`. The host must be able to disable a hung extension and surface a diagnostic error in the Dev page.

## Proposed base types

The following illustrates the direction and is not a current API:

```swift
public struct HookyExtensionID: Hashable, Codable, Sendable {
    public let rawValue: String
}

public enum HookyCapability: String, Codable, Sendable {
    case clipboardRead
    case clipboardWrite
    case fileRead
    case network
    case automation
    case accessibility
    case openURL
}

public enum HookyAdapterError: Error, Sendable {
    case permissionDenied(HookyCapability)
    case unavailable
    case unsupported
    case invalidData
    case timedOut
    case externalFailure(String)
}
```

Public value types should be `Sendable` where possible. AppKit and SwiftUI types must not leak into transport models. Artwork, for example, should be transferred as data or a file reference, and colors as Codable tokens.

## UI contributions

The first version should expose components rather than an arbitrary canvas:

- title and subtitle;
- SF Symbol or validated asset;
- semantic tint;
- one primary and one secondary command;
- progress or status;
- standard compact/expanded presentation hints.

The host context must provide the current `Locale` and report locale changes. Extensions localize their own user-facing strings; the host localizes standard buttons, statuses, and errors.

The host applies `HookyTheme`, `HookyMotion`, and `HookySurfaceLayout`. This prevents a third-party extension from breaking shared animation or hit testing.

## Security

The SDK is not ready until an extension delivery model is selected. Decisions are required for:

- an in-process Swift bundle versus a separate XPC process;
- signature and Team ID validation;
- installation directory;
- update and rollback;
- per-extension settings storage;
- CPU, memory, and event-rate limits;
- logging without leaking clipboard contents or tokens.

A separate process/XPC is preferable for third-party extensions. It is more complex, but a crashing or hung integration would not take down the panel.

## Implementation stages

### Stage 0 — beta gate: stabilize internal contracts

- [x] document existing adapters;
- [x] define dependency rules;
- [x] create the permissions matrix;
- [x] replace `Bool` with typed results;
- [x] make the Music registry internally extensible;
- [x] make the Notes registry internally extensible;
- [x] unify system event adapters;
- [x] add machine-readable capability declarations;
- [x] add test doubles and contract regression tests.

After Stage 0 and release validation, the public Hooky bar beta ships. The next stages begin after collecting and fixing real beta issues.

### Stage 1 — after beta: Core and SDK packages

- [ ] move value models into a library target;
- [ ] define semantic versioning;
- [ ] implement registry and lifecycle;
- [ ] migrate the built-in Tool adapter to the public contract;
- [ ] add compatibility unit tests.

### Stage 2 — first external integration

- [ ] create a `HelloHooky` example;
- [ ] add a Tool contribution;
- [ ] add a Compact event contribution;
- [ ] surface extension errors and state in the Dev page;
- [ ] measure CPU/RAM and crash behavior.

### Stage 3 — Clipboard and settings

- [ ] expose the Clipboard source API;
- [ ] add a standard settings schema;
- [ ] add capability prompts;
- [ ] migrate settings between versions.

### Stage 4 — distribution

- [ ] signing;
- [ ] installation and removal;
- [ ] updates and rollback;
- [ ] author documentation;
- [ ] extension project template.

## SDK 0.1 readiness criterion

SDK 0.1 is ready when an external example extension can be installed without modifying the Hooky bar repository, adds one Tool and one compact event, requests only declared capabilities, can be disabled without restarting the application, and cannot access internal stores.
