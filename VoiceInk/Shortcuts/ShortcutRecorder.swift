import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorder: View {
    /// `compact` fits inline in a settings row. `prominent` is the full-width
    /// tile of the main recording shortcut: bigger key caps, a spelled-out
    /// prompt, and Esc puts the previous shortcut back.
    enum Style {
        case compact
        case prominent
    }

    let action: ShortcutAction
    let defaultShortcut: Shortcut?
    let style: Style
    let onShortcutChanged: () -> Void

    @StateObject private var recorder = ShortcutRecorderModel()
    @State private var recorderID = UUID()
    @State private var shortcut: Shortcut?

    init(
        action: ShortcutAction,
        defaultShortcut: Shortcut? = nil,
        style: Style = .compact,
        onShortcutChanged: @escaping () -> Void = {}
    ) {
        self.action = action
        self.defaultShortcut = defaultShortcut
        self.style = style
        self.onShortcutChanged = onShortcutChanged
        _shortcut = State(initialValue: ShortcutStore.shortcut(for: action))
    }

    var body: some View {
        Group {
            switch style {
            case .compact:
                HStack(spacing: 6) {
                    recordButton
                    if offersFnKey {
                        Button {
                            bindFnKey()
                        } label: {
                            FnKeyButtonLabel()
                        }
                        .buttonStyle(.plain)
                        .disabled(recorder.isRecording)
                        .help("Bind Fn / 🌐 key")
                    }
                }
            case .prominent:
                VStack(alignment: .leading, spacing: 6) {
                    recordButton
                    if offersFnKey {
                        Button("Use Fn Key") {
                            bindFnKey()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                        .disabled(recorder.isRecording)
                        .help("Bind Fn / 🌐 key")
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.shortcutDidChange)) { notification in
            guard let changedAction = notification.object as? ShortcutAction, changedAction == action else { return }
            shortcut = ShortcutStore.shortcut(for: action)
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.shortcutRecordingDidStart)) { notification in
            guard let activeRecorderID = notification.object as? UUID, activeRecorderID != recorderID else { return }
            recorder.cancel()
        }
        .onChange(of: action) { _, newAction in
            recorder.cancel()
            recorderID = UUID()
            shortcut = ShortcutStore.shortcut(for: newAction)
        }
        .onDisappear {
            recorder.cancel()
        }
    }

    private var recordButton: some View {
        Button {
            if recorder.isRecording {
                recorder.cancel()
            } else {
                NotificationCenter.default.post(
                    name: Self.shortcutRecordingDidStart,
                    object: recorderID
                )
                let previousShortcut = shortcut
                clearShortcutBeforeRecording()
                recorder.start(action: action) { newShortcut in
                    shortcut = newShortcut
                    onShortcutChanged()
                } onCancel: {
                    // Elsewhere click-then-Esc is how a shortcut is cleared;
                    // the main shortcut must not vanish on a stray click.
                    guard style == .prominent, let previousShortcut else { return }
                    ShortcutStore.setShortcut(previousShortcut, for: action)
                    shortcut = previousShortcut
                    onShortcutChanged()
                }
            }
        } label: {
            ShortcutVisualization(
                shortcut: displayedShortcut,
                isRecording: recorder.isRecording,
                style: style
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }

    // Fn alone only makes sense as a start/stop key; on finish and utility
    // shortcuts the extra control is just noise. Hidden once Fn is bound.
    private var offersFnKey: Bool {
        guard action == .primaryRecording || action == .secondaryRecording else { return false }
        return shortcut != Self.fnShortcut
    }

    private var accessibilityLabel: String {
        if recorder.isRecording {
            return recorder.previewShortcut?.displayString ?? String(localized: "Press shortcut")
        }

        return displayedShortcut?.displayString ?? String(localized: "Set Shortcut")
    }

    private var displayedShortcut: Shortcut? {
        if recorder.isRecording {
            return recorder.previewShortcut
        }

        return shortcut ?? defaultShortcut
    }

    private func clearShortcutBeforeRecording() {
        ShortcutStore.setShortcut(nil, for: action)
        shortcut = nil
        onShortcutChanged()
    }

    private func bindFnKey() {
        recorder.cancel()
        let fn = Self.fnShortcut
        if let validationError = ShortcutValidator.validationError(for: fn, action: action) {
            NotificationManager.shared.showNotification(
                title: validationError.notificationTitle(for: fn),
                type: .error
            )
            return
        }
        ShortcutStore.setShortcut(fn, for: action)
        shortcut = fn
        onShortcutChanged()
    }

    private static let fnShortcut = Shortcut.modifierOnly(
        keyCode: UInt16(kVK_Function),
        modifierFlags: [.function]
    )

    private static let shortcutRecordingDidStart = Notification.Name("ShortcutRecorderRecordingDidStart")
}

private struct ShortcutVisualization: View {
    let shortcut: Shortcut?
    let isRecording: Bool
    let style: ShortcutRecorder.Style

    var body: some View {
        switch style {
        case .compact: compact
        case .prominent: prominent
        }
    }

    private var compact: some View {
        HStack(spacing: 4) {
            if let shortcut {
                keyCaps(for: shortcut)
            } else {
                Text(isRecording ? LocalizedStringKey("Press shortcut") : LocalizedStringKey("Set Shortcut"))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isRecording ? .primary : .secondary)
            }
        }
        .padding(4)
        .frame(minWidth: shortcut == nil ? 104 : nil, minHeight: 26)
        .fixedSize(horizontal: true, vertical: false)
        .background(tileShape(cornerRadius: 6))
    }

    private var prominent: some View {
        HStack(spacing: 6) {
            if let shortcut {
                keyCaps(for: shortcut)
            } else {
                if !isRecording {
                    Image(systemName: "keyboard")
                        .foregroundStyle(.secondary)
                }
                Text(isRecording ? LocalizedStringKey("Press the new shortcut…") : LocalizedStringKey("Click to set a shortcut"))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isRecording ? .primary : .secondary)
            }

            Spacer(minLength: 12)

            Text(isRecording ? LocalizedStringKey("Esc to cancel") : LocalizedStringKey("Change…"))
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(isRecording ? AnyShapeStyle(AppTheme.Accent.text) : AnyShapeStyle(.secondary))
                .opacity(!isRecording && shortcut == nil ? 0 : 1)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(tileShape(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private func keyCaps(for shortcut: Shortcut) -> some View {
        ForEach(Array(shortcut.displayTokens.enumerated()), id: \.offset) { _, token in
            ShortcutKeyCap(title: token, isRecording: isRecording, isLarge: style == .prominent)
        }
    }

    private func tileShape(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(isRecording ? AppTheme.Accent.fill : AppTheme.Surface.control)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isRecording ? AppTheme.Accent.border : AppTheme.Border.subtle, lineWidth: 1)
            }
    }
}

private struct ShortcutKeyCap: View {
    let title: String
    let isRecording: Bool
    var isLarge = false

    var body: some View {
        Text(title)
            .font(.system(size: isLarge ? 15 : 11, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, isLarge ? 9 : 5)
            .frame(minWidth: isLarge ? 28 : nil, minHeight: isLarge ? 28 : 18)
            .background {
                RoundedRectangle(cornerRadius: isLarge ? 6 : 4)
                    .fill(backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: isLarge ? 6 : 4)
                    .stroke(borderColor, lineWidth: 1)
            }
    }

    private var foregroundColor: Color {
        Color(NSColor.textBackgroundColor)
    }

    private var backgroundColor: Color {
        Color(NSColor.labelColor)
    }

    private var borderColor: Color {
        isRecording ? AppTheme.Accent.text : foregroundColor.opacity(0.28)
    }
}

/// Outlined, not filled like `ShortcutKeyCap`: it is an action ("bind Fn"),
/// and must not read as one more key of the shortcut shown beside it.
private struct FnKeyButtonLabel: View {
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Text(verbatim: "Fn")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(minHeight: 26)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppTheme.Border.subtle, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

final class ShortcutRecorderModel: ObservableObject {
    @Published var isRecording = false
    @Published var previewShortcut: Shortcut?

    private var localMonitor: Any?
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onCapture: ((Shortcut) -> Void)?
    private var onCancel: (() -> Void)?
    private var activeAction: ShortcutAction?
    private var pendingModifierShortcut: Shortcut?
    private var peakModifierFlags: NSEvent.ModifierFlags = []

    deinit {
        removeRecordingMonitor()
    }

    func start(
        action: ShortcutAction,
        onCapture: @escaping (Shortcut) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        cancel()

        activeAction = action
        self.onCapture = onCapture
        self.onCancel = onCancel
        isRecording = true
        previewShortcut = nil
        installRecordingMonitor()
    }

    /// Ends a recording without a new shortcut: Esc, a rejected shortcut,
    /// another recorder taking over, or the view going away.
    func cancel() {
        let cancelHandler = isRecording ? onCancel : nil
        removeRecordingMonitor()
        resetRecordingState()
        cancelHandler?()
    }

    private func finish(with shortcut: Shortcut) {
        guard let activeAction else {
            cancel()
            return
        }

        if let validationError = ShortcutValidator.validationError(for: shortcut, action: activeAction) {
            cancel()
            showErrorNotification(validationError.notificationTitle(for: shortcut))
            return
        }

        let capture = onCapture
        removeRecordingMonitor()
        resetRecordingState()

        ShortcutStore.setShortcut(shortcut, for: activeAction)
        capture?(shortcut)
    }

    private func resetRecordingState() {
        isRecording = false
        previewShortcut = nil
        onCapture = nil
        onCancel = nil
        activeAction = nil
        pendingModifierShortcut = nil
        peakModifierFlags = []
    }

    private func showErrorNotification(_ title: String) {
        Task { @MainActor in
            NotificationManager.shared.showNotification(
                title: title,
                type: .error
            )
        }
    }

    private func installRecordingMonitor() {
        if installCGEventTap() {
            return
        }
        installLocalFallbackMonitor()
    }

    private func installCGEventTap() -> Bool {
        let mask: CGEventMask = (CGEventMask(1) << CGEventType.keyDown.rawValue) |
                                (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let model = Unmanaged<ShortcutRecorderModel>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = model.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            let consumed = model.handleCGEvent(type: type, event: event)
            return consumed ? nil : Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        self.eventTap = tap
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func installLocalFallbackMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            let shouldConsume = self.handleRecordingEvent(event)
            return shouldConsume ? nil : event
        }
    }

    private func removeRecordingMonitor() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    fileprivate func handleCGEvent(type: CGEventType, event: CGEvent) -> Bool {
        guard isRecording else {
            return false
        }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        switch type {
        case .keyDown:
            return handleKeyDown(keyCode: keyCode, modifierFlags: flags)
        case .flagsChanged:
            return handleFlagsChanged(keyCode: keyCode, modifierFlags: flags)
        default:
            return false
        }
    }

    private func handleRecordingEvent(_ event: NSEvent) -> Bool {
        guard isRecording else {
            return false
        }

        switch event.type {
        case .keyDown:
            return handleKeyDown(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        case .flagsChanged:
            return handleFlagsChanged(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        default:
            return false
        }
    }

    private func handleKeyDown(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let modifiers = Shortcut.normalizedModifierFlags(modifierFlags, forKeyCode: keyCode)

        if keyCode == UInt16(kVK_Escape), modifiers.isEmpty {
            cancel()
            return true
        }

        guard !Shortcut.isModifierKeyCode(keyCode) else {
            return true
        }

        let shortcut = Shortcut.key(keyCode: keyCode, modifierFlags: modifiers)
        previewShortcut = shortcut
        finish(with: shortcut)
        return true
    }

    private func handleFlagsChanged(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let modifiers = Shortcut.normalizedModifierFlags(modifierFlags, forKeyCode: keyCode)

        if modifiers.isEmpty,
           Shortcut.isFunctionKeyCode(keyCode),
           Shortcut.normalizedModifierFlags(modifierFlags, forKeyCode: nil).contains(.function) {
            return true
        }

        if !modifiers.isEmpty {
            peakModifierFlags.formUnion(modifiers)
            let singleModifierKeyCode = Shortcut.modifierKeyCodeForSingleModifierEvent(
                keyCode: keyCode,
                modifiers: peakModifierFlags
            )
            let shortcut = Shortcut.modifierOnly(
                keyCode: singleModifierKeyCode,
                modifierFlags: peakModifierFlags
            )

            pendingModifierShortcut = shortcut
            previewShortcut = shortcut
            return true
        }

        if let pendingModifierShortcut {
            finish(with: pendingModifierShortcut)
        }

        return true
    }
}
