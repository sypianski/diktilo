import SwiftUI

struct VoiceInkButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    var isDisabled: Bool = false
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isDisabled ? AppTheme.Accent.disabled : AppTheme.Accent.primary)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct ModeEmptyStateView: View {
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Modes")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add customized modes for different contexts")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VoiceInkButton(
                title: "Add New Mode",
                action: action
            )
            .frame(maxWidth: 250)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OutputProfilesGrid: View {
    @ObservedObject var modeManager: OutputProfileManager
    let onEditConfig: (OutputProfile) -> Void

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach($modeManager.configurations) { $config in
                ConfigurationRow(
                    config: $config,
                    isEditing: false,
                    modeManager: modeManager,
                    onEditConfig: onEditConfig
                )
            }
        }
    }
}

struct DefaultModeIndicator: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)

            Text("Default")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.leading, 7)
        .padding(.trailing, 9)
        .frame(height: 24)
        .background {
            Capsule()
                .fill(AppTheme.Surface.card)
        }
        .overlay {
            Capsule()
                .strokeBorder(AppTheme.Border.control, lineWidth: 0.5)
        }
        .contentShape(Capsule())
        .help("Default mode is used when no app or website matches")
    }
}

struct ConfigurationRow: View {
    @Binding var config: OutputProfile
    let isEditing: Bool
    let modeManager: OutputProfileManager
    let onEditConfig: (OutputProfile) -> Void
    private var profileShortcut: Shortcut? {
        ShortcutStore.shortcut(for: .profile(config.id))
    }

    @ViewBuilder
    private func metadataPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.caption)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(AppTheme.Surface.control))
        .overlay(Capsule().stroke(AppTheme.Border.control, lineWidth: 0.5))
    }
    
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    ModeIconView(icon: config.icon, size: config.icon.kind == .emoji ? 20 : 16)
                }
                .frame(width: 40, height: 40)
                .background(
                    AppCardBackground(isSelected: false, cornerRadius: AppTheme.Radius.pill)
                )

                HStack(spacing: 8) {
                    Text(config.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    metadataPill(
                        icon: config.outputMode.iconName,
                        text: config.outputMode.displayName
                    )

                    if let shortcut = profileShortcut {
                        metadataPill(
                            icon: "command",
                            text: shortcut.displayString
                        )
                    }
                }

                Spacer()

                if config.isDefault {
                    DefaultModeIndicator()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onEditConfig(config)
            }

            if !config.isDefault {
                Toggle("", isOn: Binding(
                    get: { config.isEnabled },
                    set: { newValue in
                        if newValue {
                            modeManager.enableConfiguration(with: config.id)
                        } else {
                            modeManager.disableConfiguration(with: config.id)
                        }
                    }
                ))
                    .toggleStyle(SwitchToggleStyle(tint: AppTheme.Accent.primary))
                    .labelsHidden()
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .background {
            AppMaterialCardBackground(isSelected: isEditing, cornerRadius: 16)
        }
        .opacity(config.isEnabled ? 1.0 : 0.70)
    }
    
}

struct ModeAppIcon: View {
    let bundleId: String
    
    var body: some View {
        if let icon = TriggerAppIconCache.shared.icon(for: bundleId) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
        }
    }
}

struct AppGridItem: View {
    let app: (url: URL, name: String, bundleId: String, icon: NSImage)
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
                    .shadow(color: Color(NSColor.shadowColor).opacity(0.1), radius: 2, x: 0, y: 1)
                Text(app.name)
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 28)
            }
            .frame(width: 80, height: 80)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? AppTheme.Accent.fillSubtle : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? AppTheme.Accent.primary : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
