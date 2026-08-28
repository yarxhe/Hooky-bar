import AppKit
import SwiftUI

final class InterfaceModel: ObservableObject {
    @Published var expanded = false
    @Published var contentExpanded = false
    @Published var tab = 0
    private(set) var tabDirection: CGFloat = 1
    @Published var notchWidth: CGFloat = 204
    @Published var notchHeight: CGFloat = 32
    @Published var hideLeftMusicWing = false
    @Published var screenshotPreview: URL?
    @Published var showScreenshotSuccess = false
    @Published var collapseSurfaceVisible = false
    @Published private(set) var glassRevision: UInt = 0
    private var pendingCollapse: DispatchWorkItem?
    private var pendingContentSwap: DispatchWorkItem?
    private var pendingShellDismissal: DispatchWorkItem?
    private var pendingScreenshotTimeout: DispatchWorkItem?
    private var pendingSuccessDismissal: DispatchWorkItem?
    var shouldRemainExpanded: (() -> Bool)?
    var shouldCollapseToCompactPlayer: (() -> Bool)?

    func selectTab(_ value: Int) {
        guard value != tab else { return }
        tabDirection = value > tab ? 1 : -1
        withAnimation(HookyMotion.tabSwitch) { tab = value }
    }

    func pointerInside(_ inside: Bool) {
        guard !showScreenshotSuccess else { return }
        pendingCollapse?.cancel()
        if inside {
            setExpanded(true)
        } else {
            guard screenshotPreview == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.shouldRemainExpanded?() != true else { return }
                self.setExpanded(false)
            }
            pendingCollapse = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
    }

    func setExpanded(_ value: Bool) {
        if value {
            pendingContentSwap?.cancel()
            pendingShellDismissal?.cancel()
            setCollapseSurfaceVisible(false)
            guard !expanded else { return }
            refreshGlassLayers()
            setContentExpanded(true)
            withAnimation(HookyMotion.expandFromCompact) { expanded = true }
        } else {
            guard expanded || contentExpanded else { return }
            collapseContent()
        }
    }

    func presentScreenshot(_ url: URL) {
        pendingScreenshotTimeout?.cancel()
        pendingContentSwap?.cancel()
        pendingShellDismissal?.cancel()
        pendingSuccessDismissal?.cancel()
        setCollapseSurfaceVisible(false)
        refreshGlassLayers()
        setContentExpanded(true)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showScreenshotSuccess = false
            screenshotPreview = url
        }
        withAnimation(HookyMotion.expandFromCompact) {
            expanded = true
        }
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.screenshotPreview == url else { return }
            self.collapseContent { [weak self] in
                self?.screenshotPreview = nil
            }
        }
        pendingScreenshotTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
    }

    func screenshotCopied() {
        pendingCollapse?.cancel()
        pendingScreenshotTimeout?.cancel()
        pendingContentSwap?.cancel()
        pendingSuccessDismissal?.cancel()

        // Keep the full preview in place while its black surface retracts under
        // the notch. Only after it is fully hidden do we swap in the check wing.
        collapseContent { [weak self] in
            guard let self else { return }
            self.screenshotPreview = nil
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                self.showScreenshotSuccess = true
            }
            let dismissal = DispatchWorkItem { [weak self] in
                withAnimation(.easeInOut(duration: 0.22)) { self?.showScreenshotSuccess = false }
            }
            self.pendingSuccessDismissal = dismissal
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: dismissal)
        }
    }

    private func collapseContent(after completion: (() -> Void)? = nil) {
        pendingContentSwap?.cancel()
        pendingShellDismissal?.cancel()
        let animation: Animation = shouldCollapseToCompactPlayer?() == true
            ? HookyMotion.collapseToCompact
            : HookyMotion.collapseToIdle
        withAnimation(animation) {
            collapseSurfaceVisible = true
            expanded = false
        }
        let swap = DispatchWorkItem { [weak self] in
            guard let self, !self.expanded else { return }
            self.setContentExpanded(false)
            completion?()

            let dismissal = DispatchWorkItem { [weak self] in
                guard let self, !self.expanded else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    self.collapseSurfaceVisible = false
                }
            }
            self.pendingShellDismissal = dismissal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: dismissal)
        }
        pendingContentSwap = swap
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46, execute: swap)
    }

    private func setContentExpanded(_ value: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { contentExpanded = value }
    }

    private func setCollapseSurfaceVisible(_ value: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { collapseSurfaceVisible = value }
    }

    private func refreshGlassLayers() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { glassRevision &+= 1 }
    }
}
