import CoreAudio
import SwiftUI

/// Microphone list under the permission rows. A choice is saved the moment it
/// is made (and the system default is saved on first appearance), so the
/// permissions screen needs no separate microphone step.
struct OnboardingMicrophonePicker: View {
    let onSelectionSaved: () -> Void

    @ObservedObject private var audioDeviceManager = AudioDeviceManager.shared
    @State private var selectedDeviceUID: String?
    @State private var refreshIconRotation = 0.0

    private typealias MicrophoneDevice = (id: AudioDeviceID, uid: String, name: String)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if devices.isEmpty {
                emptyState
            } else {
                listHeader

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(devices, id: \.uid) { device in
                            microphoneRow(for: device)
                        }
                    }
                }
                .frame(maxHeight: 150)
                .scrollIndicators(.automatic)
            }
        }
        .onAppear {
            refreshMicrophones(selectingIfNeeded: true)
            initializeSelectionIfNeeded()
        }
        .onChange(of: audioDeviceManager.availableDevices.map(\.uid)) { _, _ in
            ensureSelectionIsAvailable()
        }
    }

    private var listHeader: some View {
        HStack {
            Text("Microphone")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.Text.secondary)

            Spacer()

            refreshButton
        }
        .padding(.horizontal, 2)
    }

    private func microphoneRow(for device: MicrophoneDevice) -> some View {
        let isSelected = selectedDeviceUID == device.uid

        return Button {
            select(device)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark" : "mic")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? AppTheme.Text.primary : AppTheme.Text.muted)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? AppTheme.Selection.fill : AppTheme.Surface.controlActive)
                    )

                Text(device.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.Text.primary)
                    .lineLimit(1)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppMaterialCardBackground(
                    isSelected: isSelected,
                    cornerRadius: 10
                )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.slash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.Text.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("No microphones found")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.Text.primary)

                Text("Connect a microphone or allow microphone access, then refresh.")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Text.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            refreshButton
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(AppMaterialCardBackground(cornerRadius: 10))
    }

    private var refreshButton: some View {
        Button {
            refreshMicrophones(selectingIfNeeded: false)
        } label: {
            Label {
                Text("Refresh")
                    .font(.system(size: 12, weight: .semibold))
            } icon: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(refreshIconRotation))
            }
            .foregroundColor(AppTheme.Text.secondary)
        }
        .buttonStyle(.plain)
        .help("Refresh Microphones")
    }

    private var devices: [MicrophoneDevice] {
        audioDeviceManager.availableDevices
    }

    private var selectedDevice: MicrophoneDevice? {
        guard let selectedDeviceUID else { return nil }
        return devices.first { $0.uid == selectedDeviceUID }
    }

    private func refreshMicrophones(selectingIfNeeded: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            refreshIconRotation += 360
        }

        audioDeviceManager.loadAvailableDevices {
            if selectingIfNeeded {
                initializeSelectionIfNeeded()
            } else {
                ensureSelectionIsAvailable()
            }
        }
    }

    private func initializeSelectionIfNeeded() {
        guard selectedDevice == nil else { return }

        if let savedDeviceID = audioDeviceManager.selectedDeviceID,
           let savedDevice = devices.first(where: { $0.id == savedDeviceID }) {
            select(savedDevice)
            return
        }

        if let savedDeviceUID = UserDefaults.standard.selectedAudioDeviceUID,
           let savedDevice = devices.first(where: { $0.uid == savedDeviceUID }) {
            select(savedDevice)
            return
        }

        if let defaultDeviceID = audioDeviceManager.getSystemDefaultDevice(),
           let defaultDevice = devices.first(where: { $0.id == defaultDeviceID }) {
            select(defaultDevice)
            return
        }

        if let first = devices.first {
            select(first)
        }
    }

    private func ensureSelectionIsAvailable() {
        if selectedDevice == nil {
            selectedDeviceUID = nil
            initializeSelectionIfNeeded()
        }
    }

    private func select(_ device: MicrophoneDevice) {
        selectedDeviceUID = device.uid
        audioDeviceManager.selectDeviceAndSwitchToCustomMode(id: device.id)
        onSelectionSaved()
    }
}
