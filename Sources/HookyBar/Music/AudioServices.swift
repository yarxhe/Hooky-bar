import Cocoa
import CoreAudio
import AudioToolbox
import Darwin
import SwiftUI

enum SystemVolume {
    fileprivate static func outputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        ) == noErr, device != 0 else { return nil }
        return device
    }

    static func current() -> Float {
        guard let device = outputDevice() else { return 0.5 }
        for address in masterVolumeAddresses() {
            if let value = readVolume(device: device, address: address) { return value }
        }

        let channelValues = channelVolumeAddresses(device: device).compactMap {
            readVolume(device: device, address: $0)
        }
        guard !channelValues.isEmpty else { return 0.5 }
        return channelValues.reduce(0, +) / Float(channelValues.count)
    }

    @discardableResult
    static func set(_ value: Float) -> Bool {
        guard let device = outputDevice() else { return false }
        let volume = min(1, max(0, value))

        for address in masterVolumeAddresses() where writeVolume(volume, device: device, address: address) {
            return true
        }

        let channelAddresses = channelVolumeAddresses(device: device)
        guard !channelAddresses.isEmpty else { return false }
        return channelAddresses.reduce(false) { changed, address in
            writeVolume(volume, device: device, address: address) || changed
        }
    }

    fileprivate static func masterVolumeAddresses() -> [AudioObjectPropertyAddress] {
        [
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
        ]
    }

    fileprivate static func channelVolumeAddresses(device: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        let channelCount = outputChannelCount(device: device)
        guard channelCount > 0 else { return [] }
        return (1...channelCount).map {
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: AudioObjectPropertyElement($0)
            )
        }
    }

    private static func outputChannelCount(device: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioBufferList>.size) else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, list) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) {
            $0 + Int($1.mNumberChannels)
        }
    }

    private static func readVolume(
        device: AudioDeviceID,
        address originalAddress: AudioObjectPropertyAddress
    ) -> Float? {
        var address = originalAddress
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var volume: Float32 = 0
        let size = UInt32(MemoryLayout<Float32>.size)
        var mutableSize = size
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &mutableSize, &volume) == noErr else {
            return nil
        }
        return min(1, max(0, volume))
    }

    private static func writeVolume(
        _ value: Float,
        device: AudioDeviceID,
        address originalAddress: AudioObjectPropertyAddress
    ) -> Bool {
        var address = originalAddress
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else { return false }
        var volume = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &volume) == noErr
    }
}

/// Событийное наблюдение за системной громкостью и сменой устройства вывода.
/// CoreAudio вызывает listener только при реальном изменении, поэтому Hooky bar
/// не приходится опрашивать громкость таймером в фоне.
final class SystemVolumeObservation: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.yarxhe.HookyBar.system-volume", qos: .utility)
    private let onChange: @Sendable () -> Void
    private var outputDevice: AudioDeviceID?
    private var observedAddresses: [AudioObjectPropertyAddress] = []
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var isRunning = false

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    func start() {
        queue.sync {
            guard !isRunning else { return }
            isRunning = true

            let systemBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self else { return }
                self.rebindOutputDevice()
                self.notifyChange()
            }
            systemListener = systemBlock
            var address = Self.defaultOutputAddress
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                queue,
                systemBlock
            )
            rebindOutputDevice()
        }
    }

    func stop() {
        queue.sync {
            guard isRunning else { return }
            isRunning = false
            removeVolumeListeners()
            if let systemListener {
                var address = Self.defaultOutputAddress
                AudioObjectRemovePropertyListenerBlock(
                    AudioObjectID(kAudioObjectSystemObject),
                    &address,
                    queue,
                    systemListener
                )
            }
            systemListener = nil
        }
    }

    private func rebindOutputDevice() {
        removeVolumeListeners()
        guard isRunning, let device = SystemVolume.outputDevice() else { return }
        outputDevice = device

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.notifyChange()
        }
        volumeListener = block

        let candidates = SystemVolume.masterVolumeAddresses()
            + SystemVolume.channelVolumeAddresses(device: device)
        for candidate in candidates {
            var address = candidate
            guard AudioObjectHasProperty(device, &address) else { continue }
            if AudioObjectAddPropertyListenerBlock(device, &address, queue, block) == noErr {
                observedAddresses.append(candidate)
            }
        }
    }

    private func removeVolumeListeners() {
        guard let device = outputDevice, let volumeListener else {
            outputDevice = nil
            observedAddresses.removeAll()
            return
        }
        for observed in observedAddresses {
            var address = observed
            AudioObjectRemovePropertyListenerBlock(device, &address, queue, volumeListener)
        }
        outputDevice = nil
        observedAddresses.removeAll()
        self.volumeListener = nil
    }

    private func notifyChange() {
        DispatchQueue.main.async(execute: onChange)
    }

    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

final class AudioSpectrumSignal: @unchecked Sendable {
    static let shared = AudioSpectrumSignal()
    private let lock = NSLock()
    private var bands = [CGFloat](repeating: 0, count: 12)
    private var level: CGFloat = 0

    func update(bands: [CGFloat], level: CGFloat) {
        lock.lock()
        self.bands = bands
        self.level = level
        lock.unlock()
    }

    func snapshot() -> (bands: [CGFloat], level: CGFloat) {
        lock.lock()
        let result = (bands, level)
        lock.unlock()
        return result
    }
}
