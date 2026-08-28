import Cocoa
import ApplicationServices

final class YandexMusicBridge {
    private let bundleIdentifier = "ru.yandex.desktop.music"
    private let operationLock = NSLock()
    private var didRequestAccessibility = false

    @discardableResult
    func setLiked(_ desired: Bool) -> Bool {
        serialized {
            guard let button = playerButton(description: "Нравится") else {
                requestAccessibilityIfNeeded()
                return false
            }
            guard let current = state(of: button) else { return desired && press(button) }
            guard current != desired else { return true }
            return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        }
    }

    @discardableResult
    func toggleDislike() -> Bool {
        setDisliked(!(ratingState()?.disliked ?? false))
    }

    @discardableResult
    func setDisliked(_ desired: Bool) -> Bool {
        serialized {
            guard let button = playerButton(description: "Не нравится") else {
                requestAccessibilityIfNeeded()
                return false
            }
            guard let current = state(of: button) else { return desired && press(button) }
            guard current != desired else { return true }
            return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        }
    }

    func ratingState() -> (liked: Bool, disliked: Bool)? {
        serialized {
            guard let player = playerElement(),
                  let likeButton = element(label: "Нравится", in: player) else { return nil }
            let dislikeButton = element(label: "Не нравится", in: player)
            return (state(of: likeButton) ?? false, dislikeButton.flatMap(state(of:)) ?? false)
        }
    }

    func playbackState() -> Bool? {
        serialized {
            guard let player = playerElement() else { return nil }
            if element(label: "Пауза", in: player) != nil { return true }
            if element(label: "Воспроизведение", in: player) != nil { return false }
            return nil
        }
    }

    @discardableResult
    func playPause() -> Bool {
        serialized {
            let succeeded = pressPlayerButton(labels: ["Пауза", "Воспроизведение"])
            if !succeeded { requestAccessibilityIfNeeded() }
            return succeeded
        }
    }

    @discardableResult
    func startPlaybackIfNeeded() -> Bool {
        serialized {
            guard let player = playerElement() else {
                requestAccessibilityIfNeeded()
                return false
            }
            if element(label: "Пауза", in: player) != nil { return true }
            let succeeded = element(label: "Воспроизведение", in: player).map {
                AXUIElementPerformAction($0, kAXPressAction as CFString) == .success
            } ?? false
            if !succeeded { requestAccessibilityIfNeeded() }
            return succeeded
        }
    }

    @discardableResult
    func previousTrack() -> Bool {
        serialized {
            let succeeded = pressPlayerButton(labels: ["Предыдущая песня"])
            if !succeeded { requestAccessibilityIfNeeded() }
            return succeeded
        }
    }

    @discardableResult
    func nextTrack() -> Bool {
        serialized {
            let succeeded = pressPlayerButton(labels: ["Следующая песня"])
            if !succeeded { requestAccessibilityIfNeeded() }
            return succeeded
        }
    }

    func nextTrackInfo() -> UpcomingTrack? {
        serialized { readNextTrackInfo() }
    }

    private func readNextTrackInfo() -> UpcomingTrack? {
        if let root = applicationElement(), let visibleQueue = queueInfo(in: root) {
            return visibleQueue
        }
        guard let player = playerElement(),
              let queueButton = element(label: "Очередь воспроизведения", in: player) else { return nil }

        guard AXUIElementPerformAction(queueButton, kAXPressAction as CFString) == .success else { return nil }
        Thread.sleep(forTimeInterval: 0.16)
        defer {
            if let root = applicationElement(), let close = element(label: "Закрыть", in: root) {
                _ = AXUIElementPerformAction(close, kAXPressAction as CFString)
            }
        }
        guard let root = applicationElement() else { return nil }
        return queueInfo(in: root)
    }

    private func serialized<T>(_ work: () -> T) -> T {
        operationLock.lock()
        defer { operationLock.unlock() }
        return work()
    }

    private func queueInfo(in root: AXUIElement) -> UpcomingTrack? {
        var flattened: [AXUIElement] = []
        var visited = 0
        flatten(root, depth: 0, visited: &visited, into: &flattened)
        guard let heading = flattened.firstIndex(where: { label(of: $0) == "Далее в очереди" }) else { return nil }

        var title: String?
        var artists: [String] = []
        for item in flattened.dropFirst(heading + 1) {
            guard let value = label(of: item) else { continue }
            if value.hasPrefix("Трек ") {
                let candidate = String(value.dropFirst("Трек ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let title {
                    if title != candidate { break }
                } else {
                    title = candidate
                }
            } else if title != nil, value.hasPrefix("Артист ") {
                artists.append(String(value.dropFirst("Артист ".count)).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        guard let title, !title.isEmpty else { return nil }
        return UpcomingTrack(title: title, artist: artists.joined(separator: ", "))
    }

    private func applicationElement() -> AXUIElement? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == bundleIdentifier
              }) else { return nil }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    private func playerElement() -> AXUIElement? {
        guard let root = applicationElement() else { return nil }
        var visited = 0
        return findElement(label: "Плеер", in: root, depth: 0, visited: &visited)
    }

    private func playerButton(description: String) -> AXUIElement? {
        guard let player = playerElement() else { return nil }
        return element(label: description, in: player)
    }

    private func pressPlayerButton(labels: [String]) -> Bool {
        guard let player = playerElement() else { return false }
        for label in labels where element(label: label, in: player).map({
            AXUIElementPerformAction($0, kAXPressAction as CFString) == .success
        }) == true { return true }
        return false
    }

    private func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    private func element(label expectedLabel: String, in root: AXUIElement) -> AXUIElement? {
        var visited = 0
        return findElement(label: expectedLabel, in: root, depth: 0, visited: &visited)
    }

    private func findElement(label expectedLabel: String, in element: AXUIElement, depth: Int, visited: inout Int) -> AXUIElement? {
        guard depth < 24, visited < 3_000 else { return nil }
        visited += 1
        if label(of: element) == expectedLabel {
            return element
        }
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return nil }
        for child in children {
            if let match = findElement(label: expectedLabel, in: child, depth: depth + 1, visited: &visited) { return match }
        }
        return nil
    }

    private func flatten(_ element: AXUIElement, depth: Int, visited: inout Int, into result: inout [AXUIElement]) {
        guard depth < 24, visited < 3_000 else { return }
        visited += 1
        result.append(element)
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return }
        for child in children { flatten(child, depth: depth + 1, visited: &visited, into: &result) }
    }

    private func label(of element: AXUIElement) -> String? {
        for attribute in [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
               let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func state(of element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
        if let number = value as? NSNumber { return number.boolValue }
        if let flag = value as? Bool { return flag }
        return nil
    }

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted(), !didRequestAccessibility else { return }
        didRequestAccessibility = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
