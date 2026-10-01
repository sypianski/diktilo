import SwiftUI

/// One always-visible line at the top of the Modes screen: the current
/// recording shortcut and a way to change it. The shortcut itself is edited in
/// Settings → Recording Shortcut (`RecordingShortcutsSection`); it used to live
/// here inside a collapsed DisclosureGroup, where nobody found it.
struct ModesGlobalSection: View {
    @State private var primaryShortcut = ShortcutStore.shortcut(for: .primaryRecording)

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .foregroundColor(.secondary)

            Text("Recording shortcut:")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Text(primaryShortcut?.displayString ?? String(localized: "Not Set"))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(AppTheme.Surface.controlActive)
                )

            Spacer()

            Button("Change in Settings") {
                NotificationCenter.default.post(
                    name: .navigateToDestination,
                    object: nil,
                    userInfo: ["destination": ViewType.settings.rawValue]
                )
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.shortcutDidChange)) { _ in
            primaryShortcut = ShortcutStore.shortcut(for: .primaryRecording)
        }
    }
}
