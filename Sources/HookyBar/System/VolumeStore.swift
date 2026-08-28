import Combine
import Foundation

/// Синхронизирует только системную громкость macOS.
final class VolumeStore: ObservableObject {
    @Published private(set) var level = CGFloat(SystemVolume.current())

    private var observation: SystemVolumeObservation?

    func startMonitoring() {
        guard observation == nil else { return }
        refresh()
        let observation = SystemVolumeObservation { [weak self] in
            self?.refresh()
        }
        self.observation = observation
        observation.start()
    }

    func setLevel(_ value: CGFloat) {
        let clamped = min(1, max(0, value))
        level = clamped
        if !SystemVolume.set(Float(clamped)) {
            refresh()
        }
    }

    func stopMonitoring() {
        observation?.stop()
        observation = nil
    }

    private func refresh() {
        let current = CGFloat(SystemVolume.current())
        if level != current { level = current }
    }
}
