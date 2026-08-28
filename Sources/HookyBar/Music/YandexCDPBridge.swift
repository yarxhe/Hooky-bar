import Cocoa
import ApplicationServices
import SwiftUI

final class YandexCDPBridge {
    private struct Target: Decodable {
        let type: String
        let url: String
        let webSocketDebuggerUrl: URL?
    }

    let port: UInt16

    private let endpoint: URL
    private let expectedBundleIdentifier: String
    private let session: URLSession
    private let operationLock = NSLock()
    private let ownershipLock = NSLock()
    private var cachedOwnerValidation: (date: Date, isValid: Bool)?

    init(port: UInt16, expectedBundleIdentifier: String) {
        self.port = port
        self.expectedBundleIdentifier = expectedBundleIdentifier
        endpoint = URL(string: "http://127.0.0.1:\(port)/json/list")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2.0
        configuration.timeoutIntervalForResource = 2.6
        session = URLSession(configuration: configuration)
    }

    /// A high, installation-specific port avoids exposing the conventional
    /// unauthenticated DevTools port 9222. Ownership is still verified before use.
    static func persistedRandomPort(defaults: UserDefaults = .standard) -> UInt16 {
        let key = "music.yandex.cdpPort"
        let stored = defaults.integer(forKey: key)
        if (49_152...65_535).contains(stored) {
            return UInt16(stored)
        }
        let generated = UInt16.random(in: 49_152...65_535)
        defaults.set(Int(generated), forKey: key)
        return generated
    }

    static func isTrustedWebSocketURL(_ url: URL, port: UInt16) -> Bool {
        guard url.scheme?.lowercased() == "ws",
              url.host == "127.0.0.1",
              url.port == Int(port),
              url.path.hasPrefix("/devtools/page/") else { return false }
        return true
    }

    func isAvailable() -> Bool {
        targetWebSocketURL() != nil
    }

    /// Returns nil when the player page is not ready, otherwise reports the
    /// real state of Yandex's play/pause control without changing playback.
    func playbackState() -> Bool? {
        let expression = """
        (() => {
          const root = document.querySelector('[aria-label="Плеер"]');
          if (!root) return null;
          if (root.querySelector('[data-test-id="PAUSE_BUTTON"], button[aria-label="Пауза"]')) return true;
          if (root.querySelector('[data-test-id="PLAY_BUTTON"], button[aria-label="Воспроизведение"]')) return false;
          return null;
        })()
        """
        return evaluate(expression) as? Bool
    }

    func currentSnapshot() -> MusicAdapterSnapshot? {
        let expression = """
        (() => {
          const root = document.querySelector('[aria-label="Плеер"]');
          const metadata = navigator.mediaSession?.metadata;
          const audio = document.querySelector('audio');
          const text = selector => (root?.querySelector(selector)?.textContent || '').trim();
          const title = metadata?.title
            || text('[data-test-id="CURRENT_TRACK_TITLE"]')
            || text('[aria-label^="Трек "]')?.replace(/^Трек\\s+/, '');
          if (!title) return null;
          const artist = metadata?.artist
            || text('[data-test-id="CURRENT_TRACK_ARTIST"]')
            || '';
          const pauseVisible = !!root?.querySelector('[data-test-id="PAUSE_BUTTON"], button[aria-label="Пауза"]');
          return {
            title,
            artist,
            duration: Number.isFinite(audio?.duration) ? audio.duration : 0,
            elapsed: Number.isFinite(audio?.currentTime) ? audio.currentTime : 0,
            isPlaying: audio ? !audio.paused : pauseVisible
          };
        })()
        """
        guard let value = evaluate(expression) as? [String: Any],
              let title = value["title"] as? String, !title.isEmpty else { return nil }
        return MusicAdapterSnapshot(
            title: title,
            artist: value["artist"] as? String ?? "",
            duration: (value["duration"] as? NSNumber)?.doubleValue ?? 0,
            elapsed: (value["elapsed"] as? NSNumber)?.doubleValue ?? 0,
            isPlaying: value["isPlaying"] as? Bool ?? false,
            artwork: nil,
            rating: ratingState().map { MusicRatingState(liked: $0.liked, disliked: $0.disliked) }
        )
    }

    func playPause() -> Bool {
        let expression = """
        (() => {
          const root = document.querySelector('[aria-label="Плеер"]');
          const button = root?.querySelector('[data-test-id="PLAY_BUTTON"], [data-test-id="PAUSE_BUTTON"]')
            || root?.querySelector('button[aria-label="Воспроизведение"], button[aria-label="Пауза"]');
          if (!button || button.disabled) return false;
          button.click();
          return true;
        })()
        """
        return evaluateBool(expression)
    }

    /// Starts playback without turning it back off when the launch path retries.
    func startPlaybackIfNeeded() -> Bool {
        let expression = """
        (() => {
          const root = document.querySelector('[aria-label="Плеер"]');
          if (!root) return false;
          const pause = root.querySelector('[data-test-id="PAUSE_BUTTON"]')
            || root.querySelector('button[aria-label="Пауза"]');
          if (pause) return true;
          const play = root.querySelector('[data-test-id="PLAY_BUTTON"]')
            || root.querySelector('button[aria-label="Воспроизведение"]');
          if (!play || play.disabled) return false;
          play.click();
          return true;
        })()
        """
        return evaluateBool(expression)
    }

    func previousTrack() -> Bool {
        click(testID: "PREVIOUS_TRACK_BUTTON")
    }

    func nextTrack() -> Bool {
        click(testID: "NEXT_TRACK_BUTTON")
    }

    func setLiked(_ desired: Bool) -> Bool {
        let desiredLiteral = desired ? "true" : "false"
        let expression = """
        (() => {
          const root = document.querySelector('[aria-label="Плеер"]');
          const button = root?.querySelector('[data-test-id="LIKE_BUTTON"]')
            || root?.querySelector('button[aria-label*="Нравится"], button[aria-label*="нравится"]');
          if (!button) return false;
          const current = button.getAttribute('aria-pressed') === 'true'
            || button.getAttribute('data-active') === 'true'
            || ['checked', 'active', 'on'].includes(button.getAttribute('data-state'))
            || /убрать|удалить/i.test(button.getAttribute('aria-label') || '');
          if (current !== \(desiredLiteral)) button.click();
          return true;
        })()
        """
        return evaluateBool(expression)
    }

    func setDisliked(_ desired: Bool) -> Bool {
        let desiredLiteral = desired ? "true" : "false"
        let expression = """
        (() => {
          const root = document.querySelector('[aria-label="Плеер"]');
          const button = root?.querySelector('[data-test-id="DISLIKE_BUTTON"]')
            || root?.querySelector('button[aria-label*="Не нравится"], button[aria-label*="не нравится"]');
          if (!button) return false;
          const current = button.getAttribute('aria-pressed') === 'true'
            || button.getAttribute('data-active') === 'true'
            || ['checked', 'active', 'on'].includes(button.getAttribute('data-state'));
          if (current !== \(desiredLiteral)) button.click();
          return true;
        })()
        """
        return evaluateBool(expression)
    }

    func toggleDislike() -> Bool {
        setDisliked(!(ratingState()?.disliked ?? false))
    }

    func ratingState() -> (liked: Bool, disliked: Bool)? {
        let expression = """
        (() => {
          const root = document.querySelector('[aria-label="Плеер"]');
          const like = root?.querySelector('[data-test-id="LIKE_BUTTON"]')
            || root?.querySelector('button[aria-label*="Нравится"], button[aria-label*="нравится"]');
          const dislike = root?.querySelector('[data-test-id="DISLIKE_BUTTON"]')
            || root?.querySelector('button[aria-label*="Не нравится"], button[aria-label*="не нравится"]');
          if (!like) return null;
          const active = button => !!button && (
            button.getAttribute('aria-pressed') === 'true'
            || button.getAttribute('data-active') === 'true'
            || ['checked', 'active', 'on'].includes(button.getAttribute('data-state'))
            || /убрать|удалить/i.test(button.getAttribute('aria-label') || '')
          );
          return {
            liked: active(like),
            disliked: active(dislike)
          };
        })()
        """
        guard let value = evaluate(expression) as? [String: Any],
              let liked = value["liked"] as? Bool else { return nil }
        return (liked, value["disliked"] as? Bool ?? false)
    }

    func seek(to seconds: Double) -> Bool {
        let expression = """
        (() => {
          const audio = document.querySelector('audio');
          if (!audio || !Number.isFinite(audio.duration)) return false;
          audio.currentTime = Math.max(0, Math.min(audio.duration, \(seconds)));
          return true;
        })()
        """
        return evaluateBool(expression)
    }

    /// The regular player exposes its queue in the DOM. Vibe currently does not,
    /// so read the same queue model used by Yandex's own player first.
    func nextTrackInfo() -> UpcomingTrack? {
        let expression = """
        (() => {
          const player = document.querySelector('[aria-label="Плеер"]');
          const fiberKey = Object.keys(player || {}).find(key => key.startsWith('__reactFiber$'));
          let fiber = fiberKey ? player[fiberKey] : null;
          let controller = null;
          while (fiber) {
            const value = fiber.memoizedProps?.value;
            if (value?.getState && value?.moveForward && value?.moveBackward) {
              controller = value;
              break;
            }
            fiber = fiber.return;
          }
          try {
            const meta = controller?.getState()?.queueState?.nextEntity?.value?.entity?.data?.meta;
            if (meta?.title) {
              return {
                title: meta.title,
                artist: (meta.artists || []).map(artist => artist.name).filter(Boolean).join(', ')
              };
            }
          } catch (_) {}

          const all = [...document.querySelectorAll('[aria-label], h1, h2, h3')];
          const heading = all.find(e => (e.textContent || '').trim() === 'Далее в очереди');
          if (!heading) return null;
          const scope = heading.closest('[role="dialog"]') || heading.parentElement?.parentElement || document;
          const title = scope.querySelector('[aria-label^="Трек "]');
          if (!title) return null;
          const titleText = (title.getAttribute('aria-label') || '').replace(/^Трек\\s+/, '').trim();
          const artists = [...scope.querySelectorAll('[aria-label^="Артист "]')]
            .map(e => (e.getAttribute('aria-label') || '').replace(/^Артист\\s+/, '').trim())
            .filter(Boolean);
          return titleText ? { title: titleText, artist: artists.join(', ') } : null;
        })()
        """
        guard let value = evaluate(expression) as? [String: Any],
              let title = value["title"] as? String, !title.isEmpty else { return nil }
        return UpcomingTrack(title: title, artist: value["artist"] as? String ?? "")
    }

    private func click(testID: String, fallbackLabel: String? = nil) -> Bool {
        let labelSelector = fallbackLabel.map { " || root?.querySelector('button[aria-label=\"\($0)\"]')" } ?? ""
        let expression = """
        (() => {
          const root = document.querySelector('[aria-label="Плеер"]');
          const button = root?.querySelector('[data-test-id="\(testID)"]')\(labelSelector);
          if (!button || button.disabled) return false;
          button.click();
          return true;
        })()
        """
        return evaluateBool(expression)
    }

    private func evaluateBool(_ expression: String) -> Bool {
        evaluate(expression) as? Bool ?? false
    }

    private func evaluate(_ expression: String) -> Any? {
        operationLock.lock()
        defer { operationLock.unlock() }
        guard let socketURL = targetWebSocketURL() else { return nil }

        let task = session.webSocketTask(with: socketURL)
        task.resume()
        let request: [String: Any] = [
            "id": 1,
            "method": "Runtime.evaluate",
            "params": ["expression": expression, "returnByValue": true, "awaitPromise": true]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let string = String(data: data, encoding: .utf8) else {
            task.cancel(with: .invalid, reason: nil)
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        Task {
            do {
                try await task.send(.string(string))
                let message = try await task.receive()
                switch message {
                case .string(let value): responseData = value.data(using: .utf8)
                case .data(let value): responseData = value
                @unknown default: break
                }
            } catch {}
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.5)
        task.cancel(with: .normalClosure, reason: nil)
        guard let responseData,
              let response = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let result = response["result"] as? [String: Any],
              let remote = result["result"] as? [String: Any] else { return nil }
        return remote["value"]
    }

    private func targetWebSocketURL() -> URL? {
        guard debuggerBelongsToExpectedApplication() else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        var result: URL?
        session.dataTask(with: endpoint) { [port] data, response, _ in
            defer { semaphore.signal() }
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let data,
                  let targets = try? JSONDecoder().decode([Target].self, from: data) else { return }
            guard let candidate = targets.first(where: {
                $0.type == "page" && $0.url.hasPrefix("music-application://")
            })?.webSocketDebuggerUrl,
                  Self.isTrustedWebSocketURL(candidate, port: port) else { return }
            result = candidate
        }.resume()
        _ = semaphore.wait(timeout: .now() + 2.2)
        return result
    }

    /// DevTools has no authentication. Before every short cache window, verify
    /// that the listening socket belongs to an executable inside Yandex Music.app.
    private func debuggerBelongsToExpectedApplication() -> Bool {
        ownershipLock.lock()
        defer { ownershipLock.unlock() }

        if let cachedOwnerValidation,
           cachedOwnerValidation.isValid,
           Date().timeIntervalSince(cachedOwnerValidation.date) < 3 {
            return true
        }

        let valid = listenerProcessIDs().contains(where: isExpectedApplicationProcess)
        // A failed lookup is not cached: Electron may still be starting after
        // the first play click and must become available immediately afterwards.
        cachedOwnerValidation = valid ? (Date(), true) : nil
        return valid
    }

    private func listenerProcessIDs() -> [pid_t] {
        let executable = URL(fileURLWithPath: "/usr/sbin/lsof")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return [] }

        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["-n", "-P", "-a", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fp"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard line.first == "p" else { return nil }
            return pid_t(line.dropFirst())
        }
    }

    private func isExpectedApplicationProcess(_ pid: pid_t) -> Bool {
        guard let expectedApplicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: expectedBundleIdentifier
        ) else { return false }

        let expectedRoot = expectedApplicationURL
            .resolvingSymlinksInPath()
            .standardizedFileURL.path + "/Contents/"
        guard let executablePath = executablePath(for: pid) else { return false }
        return executablePath.hasPrefix(expectedRoot)
    }

    private func executablePath(for pid: pid_t) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "comm="]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty?
            .resolvingExecutablePath
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }

    var resolvingExecutablePath: String {
        URL(fileURLWithPath: self).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
