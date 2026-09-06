import CoreAudio
import Foundation

/// Только анализ в памяти: системный звук не записывается и не отправляется наружу.
final class SystemAudioSpectrumAdapter {
    private var capture: AnyObject?
    private var failed = false
    private let lifecycle = DispatchQueue(label: "com.yarxhe.HookyBar.audio-capture-lifecycle")
    var onStatus: ((String) -> Void)?

    func retry() { lifecycle.async { [self] in failed = false } }

    private func status(_ key: String) {
        DispatchQueue.main.async { [weak self] in self?.onStatus?(key) }
    }

    func setActive(_ active: Bool) {
        lifecycle.async { [self] in updateCapture(active) }
    }

    private func updateCapture(_ active: Bool) {
        guard #available(macOS 14.2, *) else {
            status("settings.spectrum.unsupported")
            return
        }
        if !active {
            (capture as? ProcessTapCapture)?.stop()
            capture = nil
            if !failed { status("settings.spectrum.idle") }
            return
        }
        guard capture == nil, !failed else { return }
        let session = ProcessTapCapture()
        do {
            try session.start()
            capture = session
            status("settings.spectrum.active")
        } catch {
            // Не повторяем системный запрос на каждом обновлении трека.
            failed = true
            status("settings.spectrum.unavailable")
            NSLog("Hooky bar: system audio capture unavailable: %@", String(describing: error))
        }
    }
}

@available(macOS 14.2, *)
private final class ProcessTapCapture {
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.yarxhe.HookyBar.audio-spectrum")
    private struct CaptureError: Error { let status: OSStatus }

    func start() throws {
        do {
            let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            description.name = "Hooky bar spectrum"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try check(AudioHardwareCreateProcessTap(description, &tap))
            var format = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format))
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32, format.mSampleRate > 0 else {
                throw CaptureError(status: kAudioDeviceUnsupportedFormatError)
            }
            let config: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Hooky bar audio analysis",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]]
            ]
            try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &device))
            var channelBands = Array(repeating: [CGFloat](repeating: 0, count: 12), count: 2)
            var receivedAudio = false
            let analyzers = (0..<2).map { channel in
                AudioSpectrumAnalyzer(sampleRate: format.mSampleRate) { bands, _ in
                    channelBands[channel] = bands
                    let combined = zip(channelBands[0], channelBands[1]).map { max($0, $1) }
                    if !receivedAudio && (combined.max() ?? 0) > 0.01 {
                        receivedAudio = true
                        NSLog("Hooky bar: spectrum received non-silent audio")
                    }
                    AudioSpectrumSignal.shared.update(bands: combined, level: combined.max() ?? 0)
                }
            }
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, device, queue) { _, input, _, _, _ in
                // Буферы принадлежат CoreAudio и читаются только внутри callback.
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                var channelOffset = 0
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    let channels = max(1, Int(buffer.mNumberChannels))
                    let samples = data.assumingMemoryBound(to: Float.self)
                    let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
                    for channel in 0..<min(channels, max(0, 2 - channelOffset)) {
                        for frame in 0..<frames {
                            analyzers[channelOffset + channel].append(samples[frame * channels + channel])
                        }
                    }
                    channelOffset += channels
                }
            })
            try check(AudioDeviceStart(device, ioProc))
            NSLog("Hooky bar: spectrum capture started at %.0f Hz", format.mSampleRate)
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let ioProc {
            AudioDeviceStop(device, ioProc)
            AudioDeviceDestroyIOProcID(device, ioProc)
        }
        ioProc = nil
        if device != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(device) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        device = AudioObjectID(kAudioObjectUnknown)
        tap = AudioObjectID(kAudioObjectUnknown)
        AudioSpectrumSignal.shared.update(bands: Array(repeating: 0, count: 12), level: 0)
    }

    private func check(_ status: OSStatus) throws {
        if status != noErr { throw CaptureError(status: status) }
    }
    deinit { stop() }
}
