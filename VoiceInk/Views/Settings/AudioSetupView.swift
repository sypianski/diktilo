import CoreAudio
import SwiftUI
import UniformTypeIdentifiers

/// Sections of the Recording screen the chips at the top jump to.
enum RecordingAnchor: String, CaseIterable, Identifiable {
    case microphone
    case languages
    case panel
    case sounds
    case behavior

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .microphone: return "Microphone"
        case .languages: return "Languages"
        case .panel: return "Panel"
        case .sounds: return "Sounds"
        case .behavior: return "Behavior"
        }
    }
}

struct AudioSetupView: View {
    @ObservedObject private var audioDeviceManager = AudioDeviceManager.shared
    @ObservedObject private var mediaController = MediaController.shared
    @ObservedObject private var playbackController = PlaybackController.shared
    @EnvironmentObject private var recorderUIManager: RecorderUIManager
    @EnvironmentObject private var engine: VoiceInkEngine
    @StateObject private var levelMonitor = InputLevelMonitor()
    @State private var draggingDeviceID: String?
    @State private var showsOtherMicrophones = false
    @AppStorage(RecorderDisplaySettingsKeys.showLiveTranscript) private var showLiveTranscript = true
    @AppStorage("RecorderDestinationHUDEnabled") private var destinationHUDEnabled = true
    @State private var microphoneSourceBeforePriorityOrder: MicrophoneSourceSelection = .systemDefault
    @State private var refreshIconRotation = 0.0

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                AppScreenHeader(title: "Recording")

                jumpChips(proxy)

                Form {
                    Section {
                        inputSettingsRows
                    } header: {
                        Text("Audio Input")
                            .id(RecordingAnchor.microphone)
                    }

                    if usesPriorityOrder {
                        Section {
                            priorityOrderRows
                        } header: {
                            Text("Priority Order")
                        }
                    }

                    // Right after the microphone: what you say and how it becomes text,
                    // before how the bar looks.
                    TranscriptionSection()

                    Section {
                        panelStyleTiles

                        Toggle(isOn: $showLiveTranscript) {
                            HStack(spacing: 4) {
                                Text("Live Text Display")
                                InfoTip("Shows live text while recording with realtime models.")
                            }
                        }

                        Toggle(isOn: $destinationHUDEnabled) {
                            HStack(spacing: 4) {
                                Text("Shortcut Hints While Recording")
                                InfoTip("Show the finish shortcuts of your modes and save targets under the recording bar.")
                            }
                        }
                    } header: {
                        Text("Recording Panel")
                            .id(RecordingAnchor.panel)
                    }

                    Section {
                        CustomSoundSettingsView()
                    } header: {
                        Text("Recording Sounds")
                            .id(RecordingAnchor.sounds)
                    }

                    Section {
                        Toggle("Mute Audio While Recording", isOn: $mediaController.isSystemMuteEnabled)

                        Toggle("Pause Media While Recording", isOn: $playbackController.isPauseMediaEnabled)

                        // The delay only means something while one of the two is on.
                        if canEditResumeDelay {
                            LabeledContent {
                                resumeDelayMenu
                            } label: {
                                Text("Resume Delay")
                                Text("Time after which sound and media come back after recording.")
                            }
                            .padding(.leading, 20)
                        }
                    } header: {
                        Text("Recording Behavior")
                            .id(RecordingAnchor.behavior)
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
        }
        .onAppear {
            if !usesPriorityOrder {
                microphoneSourceBeforePriorityOrder = currentMicrophoneSource
            }
        }
        .onDisappear { levelMonitor.stop() }
        .onChange(of: engine.recordingState) { _, state in
            if state != .idle { levelMonitor.stop() }
        }
        .onChange(of: audioDeviceManager.selectedDeviceID) { _, _ in levelMonitor.stop() }
        .onChange(of: audioDeviceManager.inputMode) { _, _ in levelMonitor.stop() }
    }

    // MARK: - Jump chips

    private func jumpChips(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 8) {
            ForEach(RecordingAnchor.allCases) { anchor in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(anchor, anchor: .top)
                    }
                } label: {
                    Text(anchor.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.Text.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(AppTheme.Palette.chip))
                        .overlay(Capsule().stroke(AppTheme.Palette.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
    }

    // MARK: - Panel tiles

    private var panelStyleTiles: some View {
        HStack(spacing: 12) {
            ForEach(RecorderPanelStyle.allCases) { style in
                PanelStyleTile(
                    style: style,
                    isSelected: recorderUIManager.recorderPanelStyle == style
                ) {
                    recorderUIManager.recorderPanelStyle = style
                }
            }
        }
    }

    @ViewBuilder
    private var inputSettingsRows: some View {
        Picker("Microphone Mode", selection: inputRouteSelection) {
            Text("Selected Microphone").tag(InputRoute.singleMicrophone)
            Text("Priority Order").tag(InputRoute.priorityOrder)
        }
        .pickerStyle(.menu)

        if !usesPriorityOrder {
            Picker("Microphone", selection: microphoneSourceSelection) {
                Text(systemDefaultSourceTitle).tag(MicrophoneSourceSelection.systemDefault)

                ForEach(audioDeviceManager.availableDevices, id: \.uid) { device in
                    Text(device.name).tag(MicrophoneSourceSelection.device(device.uid))
                }
            }
            .pickerStyle(.menu)
        }

        Button {
            refreshMicrophones()
        } label: {
            Label {
                Text("Refresh Microphones")
            } icon: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(refreshIconRotation))
            }
        }
        .buttonStyle(.borderless)
        .help("Refresh Microphones")

        LabeledContent("Input Level") {
            HStack(spacing: 10) {
                if levelMonitor.failed {
                    Text("Couldn't listen to this microphone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LevelMeter(level: levelMonitor.level, isActive: levelMonitor.isRunning)
                    .frame(width: 140, height: 8)

                Button(levelMonitor.isRunning ? "Stop" : "Test") {
                    toggleLevelTest()
                }
                .controlSize(.small)
                .disabled(engine.recordingState != .idle)
            }
        }
    }

    private func toggleLevelTest() {
        if levelMonitor.isRunning {
            levelMonitor.stop()
        } else {
            levelMonitor.start(deviceID: audioDeviceManager.getCurrentDevice())
        }
    }

    @ViewBuilder
    private var priorityOrderRows: some View {
        if prioritizedDevicesInDisplayOrder.isEmpty {
            Text("Add microphones in the order Diktilo should try them.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(prioritizedDevicesInDisplayOrder) { device in
                priorityDeviceRow(for: device)
                    .onDrag {
                        draggingDeviceID = device.id
                        return NSItemProvider(object: device.id as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: PriorityReorderDelegate(
                            targetID: device.id,
                            draggingID: $draggingDeviceID,
                            move: moveDevice
                        )
                    )
            }
        }

        let others = availableDevicesNotInPriorityOrder
        if !others.isEmpty {
            DisclosureGroup(isExpanded: $showsOtherMicrophones) {
                ForEach(others, id: \.uid) { device in
                    availablePriorityDeviceRow(for: device)
                }
            } label: {
                Text("Other Microphones (\(others.count))")
            }
        }
    }

    private var inputRouteSelection: Binding<InputRoute> {
        Binding(
            get: { usesPriorityOrder ? .priorityOrder : .singleMicrophone },
            set: { route in
                switch route {
                case .singleMicrophone:
                    selectSingleMicrophoneMode()
                case .priorityOrder:
                    selectPriorityOrderMode()
                }
            }
        )
    }

    private var microphoneSourceSelection: Binding<MicrophoneSourceSelection> {
        Binding(
            get: { currentMicrophoneSource },
            set: { selection in
                microphoneSourceBeforePriorityOrder = selection
                selectMicrophoneSource(selection)
            }
        )
    }

    private func availablePriorityDeviceRow(for device: (id: AudioDeviceID, uid: String, name: String)) -> some View {
        Button {
            audioDeviceManager.addPrioritizedDevice(uid: device.uid, name: device.name)
        } label: {
            HStack(spacing: 8) {
                Label(device.name, systemImage: "plus.circle")
                    .lineLimit(1)

                Spacer()

                Text("Add…")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func priorityDeviceRow(for prioritizedDevice: PrioritizedDevice) -> some View {
        let device = audioDeviceManager.availableDevices.first { $0.uid == prioritizedDevice.id }
        let isAvailable = device != nil
        let isActive = device.map { audioDeviceManager.getCurrentDevice() == $0.id } ?? false

        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text("\(prioritizedDevice.priority + 1)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(prioritizedDevice.name)
                    .foregroundStyle(isAvailable ? .primary : .secondary)
                    .lineLimit(1)

                if !isAvailable {
                    Text("Unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isActive {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }

            Button {
                audioDeviceManager.removePrioritizedDevice(id: prioritizedDevice.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove")
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Move Up") { movePrioritizedDeviceUp(prioritizedDevice) }
                .disabled(prioritizedDevice.id == prioritizedDevicesInDisplayOrder.first?.id)
            Button("Move Down") { movePrioritizedDeviceDown(prioritizedDevice) }
                .disabled(prioritizedDevice.id == prioritizedDevicesInDisplayOrder.last?.id)
        }
    }

    /// Live reordering while a row is dragged over another.
    private func moveDevice(_ id: String, onto targetID: String) {
        var devices = prioritizedDevicesInDisplayOrder
        guard let from = devices.firstIndex(where: { $0.id == id }),
              let to = devices.firstIndex(where: { $0.id == targetID }),
              from != to else { return }
        devices.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        updatePriorities(devices)
    }

    private var currentMicrophoneSource: MicrophoneSourceSelection {
        switch audioDeviceManager.inputMode {
        case .systemDefault:
            return .systemDefault
        case .custom:
            if let selectedDeviceUID {
                return .device(selectedDeviceUID)
            }
            return .systemDefault
        case .prioritized:
            return microphoneSourceBeforePriorityOrder
        }
    }

    private func selectMicrophoneSource(_ selection: MicrophoneSourceSelection) {
        switch selection {
        case .systemDefault:
            audioDeviceManager.selectInputMode(.systemDefault)
        case .device(let uid):
            guard let device = audioDeviceManager.availableDevices.first(where: { $0.uid == uid }) else {
                audioDeviceManager.selectInputMode(.systemDefault)
                return
            }
            audioDeviceManager.selectDeviceAndSwitchToCustomMode(id: device.id)
        }
    }

    private func selectSingleMicrophoneMode() {
        selectMicrophoneSource(microphoneSourceBeforePriorityOrder)
    }

    private func selectPriorityOrderMode() {
        if !usesPriorityOrder {
            microphoneSourceBeforePriorityOrder = currentMicrophoneSource
        }
        audioDeviceManager.selectInputMode(.prioritized)
    }

    private var selectedDeviceUID: String? {
        guard let selectedDeviceID = audioDeviceManager.selectedDeviceID else { return nil }
        return audioDeviceManager.availableDevices.first { $0.id == selectedDeviceID }?.uid
    }

    private var systemDefaultSourceTitle: String {
        guard let name = audioDeviceManager.getSystemDefaultDeviceName() else {
            return String(localized: "System Default")
        }
        return String(format: String(localized: "System Default (%@)"), name)
    }

    private func refreshMicrophones() {
        withAnimation(.easeInOut(duration: 0.35)) {
            refreshIconRotation += 360
        }
        audioDeviceManager.loadAvailableDevices()
    }

    private var usesPriorityOrder: Bool {
        audioDeviceManager.inputMode == .prioritized
    }

    private var prioritizedDevicesInDisplayOrder: [PrioritizedDevice] {
        audioDeviceManager.prioritizedDevices.sorted { $0.priority < $1.priority }
    }

    private var availableDevicesNotInPriorityOrder: [(id: AudioDeviceID, uid: String, name: String)] {
        audioDeviceManager.availableDevices.filter { device in
            !audioDeviceManager.prioritizedDevices.contains { $0.id == device.uid }
        }
    }

    private var resumeDelayMenu: some View {
        Picker("Resume Delay", selection: $mediaController.audioResumptionDelay) {
            Text("0s").tag(0.0)
            Text("1s").tag(1.0)
            Text("2s").tag(2.0)
            Text("3s").tag(3.0)
            Text("4s").tag(4.0)
            Text("5s").tag(5.0)
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }

    private var canEditResumeDelay: Bool {
        mediaController.isSystemMuteEnabled || playbackController.isPauseMediaEnabled
    }

    private func movePrioritizedDeviceUp(_ device: PrioritizedDevice) {
        var devices = prioritizedDevicesInDisplayOrder
        guard let currentIndex = devices.firstIndex(where: { $0.id == device.id }),
              currentIndex > 0
        else { return }

        devices.swapAt(currentIndex, currentIndex - 1)
        updatePriorities(devices)
    }

    private func movePrioritizedDeviceDown(_ device: PrioritizedDevice) {
        var devices = prioritizedDevicesInDisplayOrder
        guard let currentIndex = devices.firstIndex(where: { $0.id == device.id }),
              currentIndex < devices.count - 1
        else { return }

        devices.swapAt(currentIndex, currentIndex + 1)
        updatePriorities(devices)
    }

    private func updatePriorities(_ devices: [PrioritizedDevice]) {
        let updatedDevices = devices.enumerated().map { index, device in
            PrioritizedDevice(id: device.id, name: device.name, priority: index, modelUID: device.modelUID)
        }
        audioDeviceManager.updatePriorities(devices: updatedDevices)
    }
}

private enum MicrophoneSourceSelection: Hashable {
    case systemDefault
    case device(String)
}

private enum InputRoute: Hashable {
    case singleMicrophone
    case priorityOrder
}

private struct PriorityReorderDelegate: DropDelegate {
    let targetID: String
    @Binding var draggingID: String?
    let move: (String, String) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            move(draggingID, targetID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

/// Bar that fills with the microphone's level while a test runs.
private struct LevelMeter: View {
    let level: Float
    let isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.Palette.chip)

                Capsule()
                    .fill(level > 0.9 ? AppTheme.Status.error : AppTheme.Status.positive)
                    .frame(width: max(isActive ? 4 : 0, proxy.size.width * CGFloat(level)))
                    .animation(.linear(duration: 0.08), value: level)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text("\(Int(level * 100))%"))
    }
}

/// One recording-panel style: a thumbnail of where it sits on the screen and its name.
private struct PanelStyleTile: View {
    let style: RecorderPanelStyle
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                ZStack(alignment: style == .notch ? .top : .bottom) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppTheme.Palette.chip)

                    switch style {
                    case .notch:
                        UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
                            .fill(AppTheme.Palette.ink)
                            .frame(width: 56, height: 14)
                    case .mini:
                        Capsule()
                            .fill(AppTheme.Palette.ink)
                            .frame(width: 44, height: 10)
                            .padding(.bottom, 8)
                    }
                }
                .frame(height: 56)

                HStack(spacing: 5) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.Accent.text)
                    }
                    Text(style.displayName)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AppTheme.Selection.fill : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? AppTheme.Palette.ink : AppTheme.Palette.rule, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
