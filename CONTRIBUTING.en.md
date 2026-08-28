# Developing Hooky bar

[Русский](CONTRIBUTING.md) · [English](CONTRIBUTING.en.md)

This document is for contributors who build Hooky bar from source or add an integration. End-user installation uses a ready-made release image and is described in the [English README](README.en.md).

## Requirements

- macOS 14 or newer;
- Xcode 26 or newer with the macOS 26 SDK: the compiler needs it for Liquid Glass APIs, while the application still supports macOS 14 through its fallback;
- Swift Package Manager (the manifest uses tools version 5.9);
- an authenticated `gh` installation (`gh auth login`) only for GitHub Actions status in the Dev page.

A Mac with a notch is recommended for visual testing of compact states, but the project can be built without one.

## Building

```bash
swift build
```

Run the debug build with Swift Package Manager:

```bash
swift run HookyBar
```

Do not run the debug process and the installed app at the same time. Both instances would independently observe the media session and system events.

## Local installation

The installation script builds a release, creates `Hooky bar.app`, installs it in `~/Applications`, restarts one fresh instance, and adds it to Login Items:

```bash
./Packaging/install.sh
```

You can temporarily override the installation root:

```bash
HOOKYBAR_INSTALL_ROOT=/path/to/folder ./Packaging/install.sh
```

Local builds use ad-hoc signing with the stable `com.yarxhe.HookyBar` bundle identifier. A public production release should use Developer ID signing, notarization, and a dedicated `.dmg` packaging flow.

## Project structure

```text
Sources/HookyBar/
├── App/          application startup and NSPanel
├── Clipboard/    clipboard, screenshots, and source adapters
├── Interface/    geometry, theme, and motion
├── Models/       shared models
├── Music/        players, snapshots, and commands
├── Notes/        note-taking integrations
├── System/       system events and Pomodoro
├── Tools/        general and developer tools
└── Views/        SwiftUI views
```

More details:

- [Architecture](Documentation/Architecture.en.md);
- [Internal adapters](Documentation/Adapters.en.md);
- [Permissions](Documentation/Permissions.en.md);
- [SDK plan](Documentation/SDK-Plan.en.md).

## Dependency rule

External applications and macOS APIs are accessed only through adapters:

```text
SwiftUI View → Store → Adapter → macOS / external application
```

A View must not run AppleScript, read the pasteboard, execute a CLI, or choose a fallback. A Store owns state and orchestration. An Adapter performs a concrete external operation.

Every new integration should follow the [internal adapter checklist](Documentation/Adapters.en.md#new-internal-adapter-checklist).

## Change guidelines

- Preserve the modular structure; every new external service gets its own adapter file.
- Do not add application-specific details to a shared store.
- Update `@Published` state only on the main queue.
- Release timers, watchers, and callbacks in `stop`.
- Do not store tokens when system authorization or Keychain can be used.
- Reflect every new capability in settings and the [permissions matrix](Documentation/Permissions.en.md).
- Reuse Hooky bar geometry and motion instead of inventing a separate surface for an integration.

## Checks before committing

Minimum checks:

```bash
./Packaging/test.sh
git diff --check
```

For interface changes, also verify:

- idle, compact, and expanded states;
- opening and closing with music playing and stopped;
- that only one app instance is running;
- button hit areas, hover, and scrolling;
- bright wallpapers behind the fully black OLED surface;
- behavior when optional system permissions are denied.

For a new adapter, test a missing app, a terminated process, permission denial, a late callback, and repeated `start`/`stop` calls.

## Release packaging

`Packaging/install.sh` is a local development tool, not a public installer. A production release pipeline should perform:

1. a release build;
2. Developer ID signing;
3. notarization;
4. `.dmg` creation;
5. installation testing on a clean user profile;
6. publishing the image and checksum in GitHub Releases.

An end user should not need to install Swift, clone the repository, or run shell scripts.
