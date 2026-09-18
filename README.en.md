<h1 align="center">Hooky bar</h1>

<p align="center">
  <a href="README.md">Русский</a> · <strong>English</strong>
</p>

<p align="center">
  A utility for the MacBook notch
</p>

<p align="center">
  <strong>Version 1.5.2</strong>
</p>

<p align="center">
  <a href="https://github.com/yarxhe/Hooky-bar/actions/workflows/ci.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/yarxhe/Hooky-bar/ci.yml?branch=master&style=flat-square&label=CI" alt="CI">
  </a>
  <a href="https://github.com/yarxhe/Hooky-bar/stargazers">
    <img src="https://img.shields.io/github/stars/yarxhe/Hooky-bar?style=flat-square&logo=github&label=Stars" alt="GitHub Stars">
  </a>
  <a href="https://github.com/yarxhe/Hooky-bar/releases/latest">
    <img src="https://img.shields.io/github/v/release/yarxhe/Hooky-bar?style=flat-square&label=Release" alt="Latest release">
  </a>
  <a href="https://github.com/yarxhe/Hooky-bar/releases">
    <img src="https://img.shields.io/github/downloads/yarxhe/Hooky-bar/total?style=flat-square&label=Downloads" alt="Release downloads">
  </a>
</p>

Hooky bar turns the MacBook notch into a compact interactive panel. Music, clipboard history, quick utilities, and important system events appear in one place without forcing you to switch between apps.

The panel stays out of the way until it is needed: hover to expand it, view compact events below the notch, and let it collapse back into the mini-player or the notch itself.

## Why Hooky bar exists

macOS spreads many useful actions across separate windows, menus, and apps. Hooky bar keeps common workflows close to the notch:

- control music without opening the player;
- return to recently copied text or screenshots;
- see device, VPN, and upcoming meeting events;
- start a focus session without losing the timer behind other windows;
- open a workspace and check CI without a separate dashboard.

## Features

### Music

- Yandex Music, Apple Music, and Spotify;
- track title, artist, and artwork;
- play/pause, previous, and next;
- seeking and system volume control;
- like and dislike where supported by the selected player;
- upcoming track, artwork-driven background, and compact visualizer;
- a mini-player around the notch during playback that smoothly shrinks its wings beside occupied menu-bar items.

### Smart clipboard

- macOS text clipboard history;
- screenshots with previews;
- one-click copying;
- pinned items;
- typo-tolerant search;
- instant preview for a newly captured screenshot.

### Utilities

- 25, 30, or 45 minute focus timer;
- quick access to Apple Notes or Obsidian;
- create a new note;
- keep-display-awake mode;
- quick access to Calendar and Downloads.

### System events

Hooky bar displays compact notifications using the same panel geometry:

- Bluetooth device connection and disconnection;
- VPN connection and disconnection;
- upcoming Apple Calendar meetings;
- newly received AirDrop files.

### Developer tools

A dedicated Dev page shows the selected workspace, Git branch, changed files, and latest GitHub Actions status. It also opens the project directly in your IDE, Terminal, Finder, or GitHub.

### Diagnostic logging

Detailed music-command and memory logging is disabled by default. After the first launch, the app creates `~/Library/Application Support/Hooky bar/config.json`:

```json
{
  "debugLogging": false
}
```

Set the value to `true` to enable logging. The change is picked up automatically without restarting the app. Logs include handling of the main interface buttons, the selected Yandex Music control channel, music-command result and latency, CDP errors, and physical memory footprint; track names and other media metadata are not recorded. Periodic `memory` readings also include `cpu_percent` and `cpu_interval_s`: average process CPU over the interval (normally 15 seconds), with 100% representing one core. The first reading establishes a baseline and has no CPU value; short peaks may exceed the average. These measurements are skipped when debug logging is disabled.

```sh
log stream --style compact --level info \
  --predicate 'process == "HookyBar" AND subsystem == "com.yarxhe.HookyBar"'
```

## Screenshots

Hooky bar uses one continuous surface for the mini-player, full panel, and compact notifications. Elements do not look like separate windows and animate from the same point near the notch.

<table>
  <tr>
    <td align="center" width="50%">
      <img src="https://i.ibb.co/gL1m0dbM/2026-08-20-04-18-36.png" alt="Hooky bar Music" width="440">
      <br><sub>Music</sub>
    </td>
    <td align="center" width="50%">
      <img src="https://i.ibb.co/3Y4NpJw9/2026-08-20-04-19-29.png" alt="Hooky bar Clipboard" width="440">
      <br><sub>Clipboard</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <img src="https://i.ibb.co/0VCcFDDb/2026-08-20-04-19-51.png" alt="Hooky bar Utilities" width="440">
      <br><sub>Utilities</sub>
    </td>
    <td align="center" width="50%">
      <img src="https://i.ibb.co/2YWYNJCx/2026-08-20-04-20-10.png" alt="Hooky bar Dev" width="440">
      <br><sub>Developer tools</sub>
    </td>
  </tr>
</table>

<p align="center">
  <img src="https://i.ibb.co/dJMH77Bv/2026-08-20-04-25-32.png" alt="Hooky bar mini-player" width="720">
  <br><sub>Mini-player and system events</sub>
</p>

## Installation

Download the 1.5.2 `.dmg` from [Releases](https://github.com/yarxhe/Hooky-bar/releases), move Hooky bar to `Applications`, and launch it. Regular users do not need Swift or a local source build.

The current build is not signed with an Apple Developer ID. On first launch, use **Open** from the context menu and allow the app in macOS security settings.

Hooky bar requires macOS 14 or newer. Its primary interface is designed for a MacBook with a notch.

## Permissions

Every system permission belongs to a specific feature and does not imply screen or audio recording. See the [permissions document](Documentation/Permissions.en.md) for details.

## Project status

Hooky bar is under active development. The current public beta is **1.5.2**. The internal architecture beta gate is complete; the remaining requirements for a stable release are tracked in [Beta readiness](Documentation/Beta-Readiness.en.md). A public SDK for third-party integrations is planned after user feedback.

To build the project or contribute an integration, see [CONTRIBUTING.en.md](CONTRIBUTING.en.md).

A [repeatable UI/performance check](Documentation/PanelPerformanceTests.md) (Russian guide) exercises panel expansion, navigation/filter buttons and scrolling while measuring CPU and memory in the installed app, without disabling animations.

September 13 local checks (Russian): [dark blur replacing glass, with before/after measurements](Documentation/Dark-Blur-2026-09-13.md), and [Yandex Music system integration and CDP limitations](Documentation/Yandex-System-Integration-2026-09-13.md). These describe the local working build, not a new public release.
