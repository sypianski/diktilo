import SwiftUI

struct OutputProfilePopover: View {
    @ObservedObject var modeManager = OutputProfileManager.shared
    let selectedModeId: UUID?
    let onSelect: ((OutputProfile) -> Void)?
    /// Optional second line under a mode's name (e.g. model and enhancement).
    let detail: ((OutputProfile) -> String?)?
    /// The recorder panel that hosts the popover: it takes that panel's palette
    /// (paper in the mini panel, charcoal in the notch). `nil` keeps the dark look.
    let surface: RecorderSurface?
    /// Shows the ⌥1–⌥0 digit that picks each mode while the recorder is up.
    let showsShortcutNumbers: Bool
    @Environment(\.colorScheme) private var systemColorScheme

    init(
        selectedModeId: UUID? = nil,
        detail: ((OutputProfile) -> String?)? = nil,
        surface: RecorderSurface? = nil,
        showsShortcutNumbers: Bool = false,
        onSelect: ((OutputProfile) -> Void)? = nil
    ) {
        self.selectedModeId = selectedModeId
        self.detail = detail
        self.surface = surface
        self.showsShortcutNumbers = showsShortcutNumbers
        self.onSelect = onSelect
    }

    private var palette: ModePopoverPalette { ModePopoverPalette(surface) }

    /// ⌥1…⌥9, then ⌥0 for the tenth enabled mode; later ones have no digit.
    private func shortcutNumber(at index: Int) -> String? {
        guard showsShortcutNumbers, index < 10 else { return nil }
        return index == 9 ? "0" : "\(index + 1)"
    }

    private var effectiveSelectedModeId: UUID? {
        modeManager.resolvedEnabledConfigurationId(preferredId: selectedModeId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Mode")
                .font(.headline)
                .foregroundColor(palette.text)
                .padding(.horizontal)
                .padding(.top, 8)

            Divider()
                .background(palette.rule)
            
            ScrollView {
                let enabledConfigs = modeManager.enabledConfigurations
                VStack(alignment: .leading, spacing: 4) {
                    if enabledConfigs.isEmpty {
                        VStack(alignment: .center, spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundColor(palette.secondaryText)
                                .font(.system(size: 16))
                            Text("No Modes Available")
                                .foregroundColor(palette.text)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    } else {
                        ForEach(Array(enabledConfigs.enumerated()), id: \.element.id) { index, config in
                            ModeRow(
                                config: config,
                                detail: detail?(config),
                                shortcutNumber: shortcutNumber(at: index),
                                palette: palette,
                                isSelected: effectiveSelectedModeId == config.id,
                                action: {
                                    if let onSelect {
                                        onSelect(config)
                                    } else {
                                        modeManager.setActiveConfiguration(config)
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(width: surface != nil ? 230 : (detail == nil ? 180 : 260))
        .frame(maxHeight: 340)
        .padding(.vertical, 8)
        .background(palette.background)
        .environment(\.colorScheme, surface == .panel ? systemColorScheme : .dark)
    }
}

/// Colours of the mode list. The mini panel's paper palette follows the system
/// appearance on its own; the notch and the standalone popovers stay dark.
struct ModePopoverPalette {
    let surface: RecorderSurface?

    init(_ surface: RecorderSurface?) {
        self.surface = surface
    }

    private var isPaper: Bool { surface == .panel }

    var background: Color { isPaper ? AppTheme.Palette.paper : Color.black }
    var text: Color { isPaper ? AppTheme.Palette.ink : AppTheme.Palette.Slot.ink }
    var secondaryText: Color { isPaper ? AppTheme.Palette.inkSecondary : AppTheme.Palette.Slot.inkSecondary }
    var rule: Color { isPaper ? AppTheme.Palette.rule : AppTheme.Palette.Slot.rule }
    var selection: Color { isPaper ? AppTheme.Palette.chip : AppTheme.Palette.Slot.chip }
}

struct ModeRow: View {
    let config: OutputProfile
    var detail: String? = nil
    var shortcutNumber: String? = nil
    var palette = ModePopoverPalette(nil)
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ModeIconView(icon: config.icon, size: config.icon.kind == .emoji ? 14 : 12, color: palette.text)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(config.name)
                        .foregroundColor(palette.text)
                        .font(.system(size: 13))
                        .lineLimit(1)

                    if let detail {
                        Text(detail)
                            .foregroundColor(palette.secondaryText)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(AppTheme.Status.positive)
                        .font(.system(size: 10))
                }

                if let shortcutNumber {
                    Text("⌥\(shortcutNumber)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(palette.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? palette.selection : Color.clear)
        .cornerRadius(4)
    }
}
