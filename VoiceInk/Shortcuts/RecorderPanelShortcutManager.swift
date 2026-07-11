import Foundation
import AppKit
import Carbon.HIToolbox

@MainActor
final class RecorderPanelShortcutManager: ObservableObject {
    private var recorderUIManager: RecorderUIManager
    private var visibilityTask: Task<Void, Never>?
    private var shortcutChangeObserver: NSObjectProtocol?
    private let visibleRecorderMonitor = ShortcutMonitor()
    
    // Double-tap Escape handling
    private var firstEscapePressTime: Date? = nil
    private let escapeDoublePressThreshold: TimeInterval = 1.5
    private var escapeTimeoutTask: Task<Void, Never>?
    
    init(recorderUIManager: RecorderUIManager) {
        self.recorderUIManager = recorderUIManager
        setupShortcutChangeObserver()
        setupVisibilityObserver()
    }

    private func setupShortcutChangeObserver() {
        shortcutChangeObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.shortcutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let action = notification.object as? ShortcutAction else { return }

            let isRelevant: Bool
            switch action {
            case .cancelRecorder, .finishWithCopy, .finishWithPaste, .finishWithEditWindow, .finishWithSaveTarget:
                isRelevant = true
            default:
                isRelevant = false
            }
            guard isRelevant else { return }

            Task { @MainActor in
                self?.refreshVisibleShortcuts()
            }
        }
    }

    private func setupVisibilityObserver() {
        visibilityTask = Task { @MainActor in
            for await isVisible in recorderUIManager.$isRecorderPanelVisible.values {
                if isVisible {
                    refreshVisibleShortcuts()
                } else {
                    visibleRecorderMonitor.stop()
                    resetEscapeState()
                }
            }
        }
    }

    private var canUseModeShortcuts: Bool {
        !OutputProfileManager.shared.enabledConfigurations.isEmpty
    }

    private func resetEscapeState() {
        firstEscapePressTime = nil
        escapeTimeoutTask?.cancel()
        escapeTimeoutTask = nil
    }
    
    private func refreshVisibleShortcuts() {
        guard recorderUIManager.isRecorderPanelVisible else {
            visibleRecorderMonitor.stop()
            resetEscapeState()
            return
        }

        var shortcuts = ShortcutStore.shortcuts(for: ShortcutAction.recorderPanelStoredActions)

        if ShortcutStore.shortcut(for: .cancelRecorder) == nil {
            shortcuts[.recorderPanelEscape] = .key(keyCode: UInt16(kVK_Escape), modifierFlags: [])
        }

        if canUseModeShortcuts {
            for (index, keyCode) in Self.digitKeyCodes.enumerated() {
                shortcuts[.recorderPanelMode(index)] = .key(
                    keyCode: keyCode,
                    modifierFlags: [.option]
                )
            }
        }

        // One-shot "finish with …" destination shortcuts. User-configured
        // bindings win; otherwise fall back to Option+C / V / E for the three
        // fixed destinations. Save-target finishers have no default binding —
        // only explicitly configured ones are registered.
        var finishShortcuts = ShortcutStore.shortcuts(for: ShortcutAction.finishDestinationActions)
        for (action, fallback) in FinishDestinationBindings.fallbacks {
            if finishShortcuts[action] == nil, !ShortcutStore.isShortcutCleared(for: action) {
                finishShortcuts[action] = fallback
            }
        }
        for target in SaveTargetManager.shared.targets {
            let action = ShortcutAction.finishWithSaveTarget(target.id)
            if let shortcut = ShortcutStore.shortcut(for: action) {
                finishShortcuts[action] = shortcut
            }
        }
        for (action, shortcut) in finishShortcuts {
            shortcuts[action] = shortcut
        }

        visibleRecorderMonitor.start(
            shortcuts: shortcuts,
            onKeyDown: { [weak self] action, _ in
                Task { @MainActor in
                    await self?.handleRecorderPanelShortcut(action)
                }
            },
            onKeyUp: { _, _ in }
        )
    }

    private func handleRecorderPanelShortcut(_ action: ShortcutAction) async {
        guard recorderUIManager.isRecorderPanelVisible else { return }

        switch action {
        case .cancelRecorder:
            guard ShortcutStore.shortcut(for: .cancelRecorder) != nil else { return }
            await recorderUIManager.cancelRecording()
        case .recorderPanelEscape:
            await handleEscapeShortcut()
        case .recorderPanelMode(let index):
            handleModeSelectionShortcut(index: index)
        case .finishWithCopy:
            await handleFinishShortcut(outputMode: .copy, notice: String(localized: "Finishing → Copy"))
        case .finishWithPaste:
            await handleFinishShortcut(outputMode: .paste, notice: String(localized: "Finishing → Paste"))
        case .finishWithEditWindow:
            await handleFinishShortcut(outputMode: .editWindow, notice: String(localized: "Finishing → Edit Window"))
        case .finishWithSaveTarget(let id):
            let name = SaveTargetManager.shared.target(withID: id)?.name
            let notice = name.map { String(format: String(localized: "Finishing → %@"), $0) }
                ?? String(localized: "Finishing → Save Target")
            await handleFinishShortcut(outputMode: .saveTarget, saveTargetID: id, notice: notice)
        default:
            break
        }
    }

    private func handleFinishShortcut(
        outputMode: OutputMode,
        saveTargetID: UUID? = nil,
        notice: String
    ) async {
        // Arm the one-shot override for this session (overrides profile mode +
        // trigger words). Consumed exactly once when delivery is built.
        DeliveryDestinationOverride.shared.arm(outputMode: outputMode, saveTargetID: saveTargetID)

        NotificationManager.shared.showNotification(title: notice, type: .info)

        // If we're still recording, run the normal stop → transcribe → deliver.
        // During .transcribing / .enhancing the override alone is enough (the
        // pipeline consumes it just before delivery), so this is a no-op there.
        await recorderUIManager.finishRecordingIfActive()
    }

    private func handleEscapeShortcut() async {
        guard ShortcutStore.shortcut(for: .cancelRecorder) == nil else { return }

        let now = Date()
        if let firstTime = firstEscapePressTime,
           now.timeIntervalSince(firstTime) <= escapeDoublePressThreshold {
            resetEscapeState()
            await recorderUIManager.cancelRecording()
            return
        }

        firstEscapePressTime = now
        NotificationManager.shared.showNotification(
            title: String(localized: "Press Esc again to cancel"),
            type: .info,
            duration: escapeDoublePressThreshold
        )
        escapeTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.escapeDoublePressThreshold ?? 1.5) * 1_000_000_000))
            await MainActor.run {
                self?.firstEscapePressTime = nil
            }
        }
    }

    private func handleModeSelectionShortcut(index: Int) {
        guard canUseModeShortcuts else { return }

        let modeManager = OutputProfileManager.shared
        let availableConfigurations = modeManager.enabledConfigurations

        guard index < availableConfigurations.count else { return }

        let selectedConfig = availableConfigurations[index]
        modeManager.setActiveConfiguration(selectedConfig)
    }

    deinit {
        if let shortcutChangeObserver {
            NotificationCenter.default.removeObserver(shortcutChangeObserver)
        }

        visibilityTask?.cancel()
        MainActor.assumeIsolated {
            visibleRecorderMonitor.stop()
            resetEscapeState()
        }
    }

    private static let digitKeyCodes: [UInt16] = [
        UInt16(kVK_ANSI_1),
        UInt16(kVK_ANSI_2),
        UInt16(kVK_ANSI_3),
        UInt16(kVK_ANSI_4),
        UInt16(kVK_ANSI_5),
        UInt16(kVK_ANSI_6),
        UInt16(kVK_ANSI_7),
        UInt16(kVK_ANSI_8),
        UInt16(kVK_ANSI_9),
        UInt16(kVK_ANSI_0)
    ]
}
