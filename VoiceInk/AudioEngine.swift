import Foundation
import AVFoundation
import CoreAudio
import os

class AudioEngine: ObservableObject {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AudioEngine")
    private lazy var engine = AVAudioEngine()
    private lazy var mixer = AVAudioMixerNode()
    @Published var isRunning = false
    @Published var audioLevel: CGFloat = 0.0
    
    private var lastUpdateTime: TimeInterval = 0
    private var inputTap: Any?
    private let updateInterval: TimeInterval = 0.05
    private let deviceManager = AudioDeviceManager.shared
    private var deviceObserver: NSObjectProtocol?
    private var isConfiguring = false
    
    init() {
        setupDeviceChangeObserver()
    }
    
    private func setupDeviceChangeObserver() {
        deviceObserver = AudioDeviceConfiguration.createDeviceChangeObserver { [weak self] in
            guard let self = self else { return }
            if self.isRunning {
                self.handleDeviceChange()
            }
        }
    }
    
    private func handleDeviceChange() {
        guard !isConfiguring else {
            logger.warning("Device change already in progress, skipping")
            return
        }
        
        isConfiguring = true
        logger.info("Handling device change - Current engine state: \(self.isRunning ? "Running" : "Stopped")")
        
        // Stop the engine first
        stopAudioEngine()
        
        // Log device change details
        let currentDeviceID = deviceManager.getCurrentDevice()
        if let deviceName = deviceManager.getDeviceName(deviceID: currentDeviceID) {
            logger.info("Switching to device: \(deviceName) (ID: \(currentDeviceID))")
        }
        
        // Wait a bit for the system to process the device change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            // Try to start with new device
            self.startAudioEngine()
            self.isConfiguring = false
            logger.info("Device change handling completed")
        }
    }
    
    private func setupAudioEngine() {
        guard inputTap == nil else { return }
        
        let bus = 0
        
        // Get the current device (either selected or fallback)
        let currentDeviceID = deviceManager.getCurrentDevice()
        
        if currentDeviceID != 0 {
            do {
                logger.info("Setting up audio engine with device ID: \(currentDeviceID)")
                // Log the device type (helps identify Bluetooth devices)
                if let deviceName = deviceManager.getDeviceName(deviceID: currentDeviceID) {
                    let isBluetoothDevice = deviceName.lowercased().contains("bluetooth")
                    logger.info("Device type: \(isBluetoothDevice ? "Bluetooth" : "Standard") - \(deviceName)")
                }
                
                try configureAudioSession(with: currentDeviceID)
            } catch {
                logger.error("Audio engine setup failed: \(error.localizedDescription)")
                logger.error("Device ID: \(currentDeviceID)")
                if let deviceName = deviceManager.getDeviceName(deviceID: currentDeviceID) {
                    logger.error("Failed device name: \(deviceName)")
                }
                // Don't return here, let it try with default device
            }
        } else {
            logger.info("No specific device available, using system default")
        }
        
        // Wait briefly for device configuration to take effect
        Thread.sleep(forTimeInterval: 0.05)
        
        // Log input format details
        let inputFormat = engine.inputNode.inputFormat(forBus: bus)
        logger.info("""
            Input format details:
            - Sample Rate: \(inputFormat.sampleRate)
            - Channel Count: \(inputFormat.channelCount)
            - Common Format: \(inputFormat.commonFormat.rawValue)
            
            - Channel Layout: \(inputFormat.channelLayout?.layoutTag ?? 0)
            """)
        
        inputTap = engine.inputNode.installTap(onBus: bus, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
            self?.processAudioBuffer(buffer)
        }
    }
    
    private func configureAudioSession(with deviceID: AudioDeviceID) throws {
        logger.info("Starting audio session configuration for device ID: \(deviceID)")
        // Get the audio format from the selected device
        let streamFormat = try AudioDeviceConfiguration.configureAudioSession(with: deviceID)
        logger.info("Got stream format: \(streamFormat.mSampleRate)Hz, \(streamFormat.mChannelsPerFrame) channels")
        
        // Configure the input node to use the selected device
        let inputNode = engine.inputNode
        guard let audioUnit = inputNode.audioUnit else {
            logger.error("Failed to get audio unit from input node")
            throw AudioConfigurationError.failedToGetAudioUnit
        }
        logger.info("Got audio unit from input node")
        
        // Set the device for the audio unit
        try AudioDeviceConfiguration.configureAudioUnit(audioUnit, with: deviceID)
        logger.info("Configured audio unit with device")
        
        // Reset the engine to apply the new configuration
        engine.stop()
        try engine.reset()
        logger.info("Reset audio engine")
        
        // Use async dispatch instead of thread sleep
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 0.05)
            self.logger.info("Audio configuration delay completed")
        }
    }
    
    func startAudioEngine() {
        guard !isRunning else { return }
        
        logger.info("Starting audio engine")
        
        do {
            setupAudioEngine()
            logger.info("Audio engine setup completed")
            
            try engine.prepare()
            logger.info("Audio engine prepared")
            
            try engine.start()
            isRunning = true
            
            // Log active device and configuration details
            let currentDeviceID = deviceManager.getCurrentDevice()
            if let deviceName = deviceManager.getDeviceName(deviceID: currentDeviceID) {
                let isBluetoothDevice = deviceName.lowercased().contains("bluetooth")
                logger.info("""
                    Audio engine started successfully:
                    - Device: \(deviceName)
                    - Device ID: \(currentDeviceID)
                    - Device Type: \(isBluetoothDevice ? "Bluetooth" : "Standard")
                    - Engine Status: Running
                    """)
            }
        } catch {
            logger.error("""
                Audio engine start failed:
                - Error: \(error.localizedDescription)
                - Error Details: \(error)
                - Current Device ID: \(self.deviceManager.getCurrentDevice())
                - Engine State: \(self.engine.isRunning ? "Running" : "Stopped")
                """)
            // Clean up on failure
            stopAudioEngine()
        }
    }
    
    func stopAudioEngine() {
        guard isRunning else { return }
        
        logger.info("Stopping audio engine")
        if let tap = inputTap {
            engine.inputNode.removeTap(onBus: 0)
            inputTap = nil
        }
        
        engine.stop()
        
        // Complete cleanup of the engine
        engine = AVAudioEngine() // Create a fresh instance
        mixer = AVAudioMixerNode() // Reset mixer
        
        isRunning = false
        audioLevel = 0.0
        logger.info("Audio engine stopped and reset")
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = buffer.frameLength
        
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastUpdateTime >= updateInterval else { return }
        lastUpdateTime = currentTime
        
        // Use vDSP for faster processing
        var sum: Float = 0
        for frame in 0..<Int(frameCount) {
            let sample = abs(channelData[frame])
            sum += sample
        }
        
        let average = sum / Float(frameCount)
        let level = CGFloat(average)
        
        // Apply higher scaling for built-in microphone
        let currentDeviceID = deviceManager.getCurrentDevice()
        let isBuiltInMic = deviceManager.getDeviceName(deviceID: currentDeviceID)?.lowercased().contains("built-in") ?? false
        let scalingFactor: CGFloat = isBuiltInMic ? 11.0 : 5.0  // Higher scaling for built-in mic
        
        DispatchQueue.main.async {
            self.audioLevel = min(max(level * scalingFactor, 0), 1)
        }
    }
    
    deinit {
        if let observer = deviceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        stopAudioEngine()
    }
}

