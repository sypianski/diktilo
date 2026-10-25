import AVFoundation
import CoreAudio
import Foundation

/// Live level of a microphone for the Recording screen's "Test" button, so a
/// microphone can be checked without starting a recording. It listens for a
/// few seconds on the device the recorder would use and stops by itself.
@MainActor
final class InputLevelMonitor: ObservableObject {
    /// 0...1 on a decibel scale (-60 dB is 0, 0 dB is 1).
    @Published private(set) var level: Float = 0
    @Published private(set) var isRunning = false
    @Published private(set) var failed = false

    private var engine: AVAudioEngine?
    private var stopTask: Task<Void, Never>?

    private static let listenSeconds: UInt64 = 15

    func start(deviceID: AudioDeviceID) {
        stop()
        failed = false

        let engine = AVAudioEngine()
        let input = engine.inputNode

        if let unit = input.audioUnit {
            var device = deviceID
            AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &device,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            failed = true
            return
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }

            var sum: Float = 0
            for index in 0..<count { sum += samples[index] * samples[index] }
            let rms = (sum / Float(count)).squareRoot()
            let decibels = 20 * log10(max(rms, 0.000_001))
            let normalized = max(0, min(1, (decibels + 60) / 60))

            Task { @MainActor in self?.level = normalized }
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            failed = true
            return
        }

        self.engine = engine
        isRunning = true

        stopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.listenSeconds * 1_000_000_000)
            if !Task.isCancelled { self?.stop() }
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil

        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        isRunning = false
        level = 0
    }

    deinit {
        stopTask?.cancel()
    }
}
