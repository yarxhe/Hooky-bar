# Permissions and system access

[Русский](Permissions.md) · [English](Permissions.en.md)

Hooky bar uses system access only when the related feature is enabled or first used. Some file sources begin monitoring with the application. A permission does not imply continuous screen recording or audio capture.

| Access | Purpose | When it is needed | Required |
|---|---|---|---:|
| Automation / Apple Events | Control Apple Music and Spotify, and create an Apple Notes note | On the first command sent to the corresponding application | no |
| Accessibility | Fallback control for the native Yandex Music app when CDP is unavailable | When using a Yandex Music feature that needs the fallback | no |
| Bluetooth | Device connection and disconnection events | After Bluetooth events are enabled | no |
| Calendar | Upcoming meetings from Apple Calendar | After Calendar integration is enabled | no |
| Desktop Folder | Read screenshots when the screenshot directory is on the Desktop | When clipboard screenshot monitoring starts | no |
| Downloads Folder | Detect newly received AirDrop files in Downloads | After AirDrop events are enabled | no |
| Local connection | Connect to the Yandex Music CDP endpoint on `127.0.0.1` | When using the CDP bridge; this normally has no separate system prompt | no |

## Permissions the application must not request

- Screen Recording;
- Microphone;
- Camera;
- Full Disk Access;
- Contacts;
- Photos.

The visualizer does not record system audio. It uses available application state and visual generation, so screen and audio recording permissions are not required.

## Behavior after denial

- The main panel keeps working.
- An unavailable capability is hidden or its command returns a typed failure.
- The application must not reopen a system prompt on every polling tick.
- The user can disable an optional monitor in settings.

## Rule for the future SDK

An extension must declare its capabilities in its manifest. The host explains why access is needed before the system prompt and does not start an adapter until its capability is allowed.

Installing an extension does not automatically grant it a system permission. Unused capabilities must remain inactive.
