import Cocoa
import ApplicationServices
import SwiftUI
import Network

final class YandexCDPBridge {
    private struct Target: Decodable {
        let type: String
        let url: String
        let webSocketDebuggerUrl: URL?
    }

    let port: UInt16

    private let expectedBundleIdentifier: String
    private let operationLock = NSLock()
    private let commandLock = NSLock()
    private let ownershipLock = NSLock()
    private let discoveryLock = NSLock()
    private let targetLock = NSLock()
    private let requestIDLock = NSLock()
    private var cachedOwnerValidation: (date: Date, isValid: Bool)?
    private var cachedTarget: URL?
    private var discoveryRetryAfter: Date?
    private var nextRequestID = 0
    private let clock: () -> Date
    private let ownerProbe: (() -> Bool)?
    private let connectionFactory: (NWEndpoint, NWParameters) -> NWConnection
    private let replyTimeout: TimeInterval

    init(port: UInt16, expectedBundleIdentifier: String,
         clock: @escaping () -> Date = Date.init, ownerProbe: (() -> Bool)? = nil,
         connectionFactory: @escaping (NWEndpoint, NWParameters) -> NWConnection = { NWConnection(to: $0, using: $1) },
         replyTimeout: TimeInterval = 2.5) {
        self.port = port
        self.expectedBundleIdentifier = expectedBundleIdentifier
        self.clock = clock
        self.ownerProbe = ownerProbe
        self.connectionFactory = connectionFactory
        self.replyTimeout = replyTimeout
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
              url.user == nil, url.password == nil, url.fragment == nil,
              url.path.hasPrefix("/devtools/page/") else { return false }
        return true
    }

    func isAvailable() -> Bool {
        operationLock.lock()
        defer { operationLock.unlock() }
        return targetWebSocketURL() != nil
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
          const like = root?.querySelector('[data-test-id="LIKE_BUTTON"]')
            || root?.querySelector('button[aria-label*="Нравится"], button[aria-label*="нравится"]');
          const dislike = root?.querySelector('[data-test-id="DISLIKE_BUTTON"]')
            || root?.querySelector('button[aria-label*="Не нравится"], button[aria-label*="не нравится"]');
          const active = button => !!button && (
            button.getAttribute('aria-pressed') === 'true'
            || button.getAttribute('data-active') === 'true'
            || ['checked', 'active', 'on'].includes(button.getAttribute('data-state'))
            || /убрать|удалить/i.test(button.getAttribute('aria-label') || '')
          );
          return {
            title,
            artist,
            duration: Number.isFinite(audio?.duration) ? audio.duration : 0,
            elapsed: Number.isFinite(audio?.currentTime) ? audio.currentTime : 0,
            isPlaying: audio ? !audio.paused : pauseVisible,
            liked: active(like),
            disliked: active(dislike)
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
            rating: MusicRatingState(
                liked: value["liked"] as? Bool ?? false,
                disliked: value["disliked"] as? Bool ?? false
            )
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
        return evaluateBool(expression, freshConnection: true, retryOnFailure: false)
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
        return evaluateBool(expression, freshConnection: true)
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
        return evaluateBool(expression, freshConnection: true)
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
        return evaluateBool(expression, freshConnection: true)
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
        return evaluateBool(expression, freshConnection: true)
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
        return evaluateBool(expression, freshConnection: true, retryOnFailure: false)
    }

    private func evaluateBool(
        _ expression: String,
        freshConnection: Bool = false,
        retryOnFailure: Bool = true
    ) -> Bool {
        evaluate(
            expression,
            freshConnection: freshConnection,
            retryOnFailure: retryOnFailure
        ) as? Bool ?? false
    }

    private func evaluate(
        _ expression: String,
        freshConnection: Bool = false,
        retryOnFailure: Bool = true
    ) -> Any? {
        let evaluationLock = freshConnection ? commandLock : operationLock
        evaluationLock.lock()
        defer { evaluationLock.unlock() }
        let evaluationStartedAt = Date()

        // Yandex Electron retires idle DevTools sockets after only a few seconds.
        // A short-lived native connection avoids stale-socket latency and the
        // CFNetwork retention observed in the repeated-request regression test.
        let attemptCount = retryOnFailure ? 2 : 1
        for attempt in 0..<attemptCount {
            guard let socketURL = targetWebSocketURL(bypassBackoff: freshConnection) else { return nil }
            let requestID = makeRequestID()
            let request: [String: Any] = [
                "id": requestID,
                "method": "Runtime.evaluate",
                "params": [
                    "expression": expression,
                    "returnByValue": true,
                    "awaitPromise": true,
                    // Chromium may reject media playback initiated by an evaluated
                    // synthetic click unless DevTools marks it as a user gesture.
                    "userGesture": true
                ]
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: request) else { return nil }
            let parameters = NWParameters.tcp
            let webSocket = NWProtocolWebSocket.Options()
            webSocket.autoReplyPing = true
            webSocket.maximumMessageSize = 512 * 1024
            parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
            let connection = connectionFactory(.url(socketURL), parameters)
            let operation = CDPLocalRequest(connection: connection, kind: .evaluate(requestID), message: data)
            operation.start()
            // Always tear down the receive and connection,
            // including successful replies and every early/timeout/error exit.
            defer {
                operation.stop()
            }
            if let responseData = operation.reply.take(timeout: replyTimeout),
               let response = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               (response["id"] as? NSNumber)?.intValue == requestID,
               let result = response["result"] as? [String: Any],
               let remote = result["result"] as? [String: Any] {
                if freshConnection {
                    HookyDiagnostics.bridge(
                        "event=command_response attempt=\(attempt + 1) latency_ms=\(Int(Date().timeIntervalSince(evaluationStartedAt) * 1_000))"
                    )
                }
                return remote["value"]
            }

            HookyDiagnostics.bridge(
                "event=evaluate_failure mode=\(freshConnection ? "command" : "background") attempt=\(attempt + 1)",
                isError: true
            )
            clearCachedTarget()
            if attempt + 1 < attemptCount { continue }
        }
        return nil
    }

    private func targetWebSocketURL(bypassBackoff: Bool = false) -> URL? {
        discoveryLock.lock()
        defer { discoveryLock.unlock() }
        guard debuggerBelongsToExpectedApplication(bypassBackoff: bypassBackoff) else {
            clearCachedTarget()
            return nil
        }
        // The page target remains valid for the lifetime of its renderer. A
        // failed WebSocket command clears this cache and discovers a new target;
        // Avoid polling /json/list on every snapshot.
        if let cachedTarget = cachedTargetURL() { return cachedTarget }
        targetLock.lock()
        let canDiscover = bypassBackoff || discoveryRetryAfter.map { clock() >= $0 } != false
        targetLock.unlock()
        guard canDiscover else { return nil }
        let connection = connectionFactory(.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!), .tcp)
        let message = Data("GET /json/list HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nAccept: application/json\r\nConnection: close\r\n\r\n".utf8)
        let operation = CDPLocalRequest(connection: connection, kind: .discovery, message: message)
        operation.start()
        defer { operation.stop() }
        let data = operation.reply.take(timeout: min(2.2, replyTimeout))
        let targets = data.flatMap { try? JSONDecoder().decode([Target].self, from: $0) }
        let candidate = targets?.first(where: { $0.type == "page" && $0.url.hasPrefix("music-application://") })?.webSocketDebuggerUrl
        let result = candidate.flatMap { Self.isTrustedWebSocketURL($0, port: port) ? $0 : nil }
        targetLock.lock()
        cachedTarget = result
        discoveryRetryAfter = result == nil ? clock().addingTimeInterval(3) : nil
        targetLock.unlock()
        return result
    }

    private func cachedTargetURL() -> URL? {
        targetLock.lock()
        defer { targetLock.unlock() }
        return cachedTarget
    }

    private func clearCachedTarget() {
        targetLock.lock()
        cachedTarget = nil
        targetLock.unlock()
    }

    private func makeRequestID() -> Int {
        requestIDLock.lock()
        defer { requestIDLock.unlock() }
        nextRequestID &+= 1
        return nextRequestID
    }

    /// DevTools has no authentication. Before every short cache window, verify
    /// that the listening socket belongs to an executable inside Yandex Music.app.
    private func debuggerBelongsToExpectedApplication(bypassBackoff: Bool) -> Bool {
        ownershipLock.lock()
        defer { ownershipLock.unlock() }

        if let cachedOwnerValidation,
           clock().timeIntervalSince(cachedOwnerValidation.date) < (cachedOwnerValidation.isValid ? 15 : 3),
           cachedOwnerValidation.isValid || !bypassBackoff {
            return cachedOwnerValidation.isValid
        }

        let valid = ownerProbe?() ?? listenerProcessIDs().contains(where: isExpectedApplicationProcess)
        // Background failures back off. Explicit commands bypass the negative
        // cache, so a just-started player can respond immediately.
        cachedOwnerValidation = (clock(), valid)
        return valid
    }

    private func listenerProcessIDs() -> [pid_t] {
        let executable = URL(fileURLWithPath: "/usr/sbin/lsof")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return [] }
        guard let result = BoundedProcess.run(
            executable: executable,
            arguments: ["-n", "-P", "-a", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fp"],
            timeout: 1,
            outputLimit: 64 * 1_024
        ), result.terminationStatus == 0,
           let text = String(data: result.output, encoding: .utf8) else { return [] }
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
        guard let result = BoundedProcess.run(
            executable: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-p", String(pid), "-o", "comm="],
            timeout: 1,
            outputLimit: 16 * 1_024
        ), result.terminationStatus == 0 else { return nil }
        return String(data: result.output, encoding: .utf8)?
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
