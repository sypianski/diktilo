import SwiftUI

/// Marks the mode the main shortcut runs (the stored `isDefault` flag).
struct MainShortcutModeIndicator: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "keyboard")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.Palette.onAmber)

            Text("Main Shortcut")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.Palette.onAmber)
                .lineLimit(1)
        }
        .padding(.leading, 7)
        .padding(.trailing, 9)
        .frame(height: 24)
        .background {
            Capsule()
                .fill(AppTheme.Palette.amber)
        }
        .contentShape(Capsule())
        .help("The main shortcut runs this mode when no app or website trigger matches.")
    }
}

struct ConfigurationRow: View {
    @Binding var config: OutputProfile
    let isEditing: Bool
    let modeManager: OutputProfileManager
    let onEditConfig: (OutputProfile) -> Void
    let onDelete: (OutputProfile) -> Void
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
                    MainShortcutModeIndicator()
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
                    .help(config.isEnabled ? LocalizedStringKey("Turn this mode off") : LocalizedStringKey("Turn this mode on"))
            }

            // The main shortcut's mode can't go: it would leave the shortcut
            // without a mode. Pick another one in "Main Shortcut" first.
            Button {
                onDelete(config)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(config.isDefault)
            .help(config.isDefault ? LocalizedStringKey("The main shortcut uses this mode. Choose another mode under Main Shortcut to delete this one.") : LocalizedStringKey("Delete Mode"))
            .accessibilityLabel(Text("Delete Mode"))
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
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
