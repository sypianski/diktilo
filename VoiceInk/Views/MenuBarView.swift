import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var engine: VoiceInkEngine
    @EnvironmentObject var recorderUIManager: RecorderUIManager
    @EnvironmentObject var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject var whisperModelManager: WhisperModelManager
    @EnvironmentObject var recordingShortcutManager: RecordingShortcutManager
    @EnvironmentObject var menuBarManager: MenuBarManager
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var aiService: AIService
    @EnvironmentObject var updaterViewModel: UpdaterViewModel
    @ObservedObject private var modeManager = OutputProfileManager.shared
    @ObservedObject var audioDeviceManager = AudioDeviceManager.shared
    @AppStorage("hasCompletedOnboardingV2") private var hasCompletedOnboardingV2 = false
    
    var body: some View {
        VStack {
            if hasCompletedOnboardingV2 {
                completedOnboardingMenu
            } else {
                onboardingMenu
            }
        }
    }

    /// "Start recording ⌃⌥␣" or, while a recording runs, "Stop recording".
    private var recordingToggleTitle: String {
        if engine.recordingState == .recording {
            return String(localized: "Stop Recording")
        }
        let title = String(localized: "Start Recording")
        guard let shortcut = ShortcutStore.shortcut(for: .primaryRecording) else { return title }
        return "\(title)  \(shortcut.displayString)"
    }

    private var currentMicrophoneName: String {
        let currentID = audioDeviceManager.getCurrentDevice()
        return audioDeviceManager.availableDevices.first { $0.id == currentID }?.name
            ?? String(localized: "None")
    }

    private var onboardingMenu: some View {
        Group {
            Button("Continue Onboarding") {
                menuBarManager.focusMainWindow()
            }

            Divider()

            Button("Quit Diktilo") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var completedOnboardingMenu: some View {
        Group {
            Button(recordingToggleTitle) {
                recorderUIManager.handleToggleRecorderPanelNotification()
            }

            Divider()

            Menu {
                ForEach(modeManager.enabledConfigurations) { config in
                    Button {
                        modeManager.setActiveConfiguration(config)
                    } label: {
                        let isActive = modeManager.currentEffectiveConfiguration?.id == config.id
                        Text(isActive ? "\(config.name)  ✓" : config.name)
                    }
                }

                if modeManager.enabledConfigurations.isEmpty {
                    Text("No modes available")
                        .foregroundColor(.secondary)
                }

                Divider()

                Button("Manage Modes") {
                    menuBarManager.openMainWindowAndNavigate(to: "Modes")
                }
            } label: {
                HStack {
                    Image(systemName: "sparkles.square.fill.on.square")
                        .font(.system(size: 11, weight: .medium))
                    let activeMode = modeManager.currentEffectiveConfiguration
                    Text(String(format: String(localized: "Mode: %@"), activeMode?.name ?? String(localized: "None")))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                }
            }

            Menu {
                ForEach(audioDeviceManager.availableDevices, id: \.id) { device in
                    Button {
                        audioDeviceManager.selectDeviceAndSwitchToCustomMode(id: device.id)
                    } label: {
                        let isActive = audioDeviceManager.getCurrentDevice() == device.id
                        Text(isActive ? "\(device.name)  ✓" : device.name)
                    }
                }

                if audioDeviceManager.availableDevices.isEmpty {
                    Text("No devices available")
                        .foregroundColor(.secondary)
                }
            } label: {
                HStack {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11, weight: .medium))
                    Text(String(format: String(localized: "Microphone: %@"), currentMicrophoneName))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                }
            }

            Divider()

            Menu("Last Transcription") {
                Button("Copy") {
                    LastTranscriptionService.copyLastTranscription(from: engine.modelContext)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Retry") {
                    LastTranscriptionService.retryLastTranscription(
                        from: engine.modelContext,
                        transcriptionModelManager: transcriptionModelManager,
                        serviceRegistry: engine.serviceRegistry,
                        enhancementService: enhancementService
                    )
                }
            }

            Button("History") {
                menuBarManager.openHistoryWindow()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            
            Divider()

            Button("Open Diktilo") {
                menuBarManager.focusMainWindow()
            }

            Button("Settings") {
                menuBarManager.openMainWindowAndNavigate(to: "Settings")
            }
            .keyboardShortcut(",", modifiers: .command)

            if UpdaterViewModel.isEnabled {
                CheckForUpdatesView(updaterViewModel: updaterViewModel)
            }

            Button("Quit Diktilo") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
