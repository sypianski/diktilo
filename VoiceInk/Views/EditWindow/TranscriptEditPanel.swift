import AppKit
import SwiftUI

// MARK: - Manager

@MainActor
final class TranscriptEditManager {
    static let shared = TranscriptEditManager()
    private init() {}

    /// UserDefaults key toggling Vim mode inside the edit window.
    static let vimEnabledKey = "EditWindowVimEnabled"

    private var panel: TranscriptEditPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var previousApp: NSRunningApplication?

    var isVisible: Bool { panel?.isVisible == true }

    /// Present the edit window with the transcript. `onDone` is invoked once the
    /// panel closes (whether committed or cancelled).
    func present(text: String, onDone: (() -> Void)? = nil, saveToWorek: Bool = true) {
        // Replacing an open window: dismiss the old one silently first.
        if isVisible { hide() }

        previousApp = NSWorkspace.shared.frontmostApplication

        let vimEnabled = UserDefaults.standard.bool(forKey: Self.vimEnabledKey)
        let size = Self.preferredSize(for: text)
        let newPanel = TranscriptEditPanel(size: size)

        let view = TranscriptEditView(
            initialText: text,
            vimEnabled: vimEnabled,
            onCommit: { [weak self] finalText in
                _ = ClipboardManager.setClipboard(finalText)
                SoundManager.shared.playStopSound()
                self?.hide()
                onDone?()
            },
            onCancel: { [weak self] in
                self?.hide()
                onDone?()
            },
            onSaveToWorek: saveToWorek ? { [weak self] savedText in
                Task { @MainActor in
                    WorekStore.shared.add(text: savedText)
                    SoundManager.shared.playStopSound()
                    self?.hide()
                    onDone?()
                }
            } : nil,
            onTextChange: { [weak newPanel] newText in
                newPanel?.resizeAnimated(for: newText)
            }
        )

        let controller = NSHostingController(rootView: AnyView(view))
        newPanel.contentView = controller.view
        hostingController = controller
        panel = newPanel

        newPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        newPanel.makeKey()
    }

    func hide() {
        guard isVisible else { return }
        panel?.orderOut(nil)
        panel = nil
        hostingController = nil
        previousApp?.activate(options: .activateIgnoringOtherApps)
        previousApp = nil
    }

    /// Sizes the window to fit the transcript, growing up to 90% of screen height.
    static func preferredSize(for text: String) -> NSSize {
        let width: CGFloat = 620
        // Measure the actual laid-out text height for this exact font/width so
        // the window fits the content instead of relying on a char-count guess
        // (which under-counted wrapped lines and left the text scrolling).
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        // Usable text width = window width − text insets (8·2) − container
        // line-fragment padding (5·2), matching VimTextView's setup.
        let textWidth = width - (8 * 2) - (5 * 2)
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let bodyHeight = ceil(measured.height) + (8 * 2) + lineHeight  // + insets + caret line
        let chromeHeight: CGFloat = 44 + 40                            // header + hint bar
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let maxHeight = screenHeight * 0.90
        let height = min(max(bodyHeight + chromeHeight, 220), maxHeight)
        return NSSize(width: width, height: height)
    }

}

// MARK: - Panel

final class TranscriptEditPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func resizeAnimated(for text: String) {
        let newSize = TranscriptEditManager.preferredSize(for: text)
        guard abs(newSize.height - frame.height) > 4 else { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let newX = frame.minX
        let newY = screen.visibleFrame.midY - newSize.height / 2 + 40
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(NSRect(origin: NSPoint(x: newX, y: newY), size: newSize), display: true)
        }
    }

    init(size: NSSize) {
        let origin = TranscriptEditPanel.centeredOrigin(for: size)
        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        minSize = NSSize(width: 420, height: 200)
    }

    private static func centeredOrigin(for size: NSSize) -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let x = screen.visibleFrame.midX - size.width / 2
        let y = screen.visibleFrame.midY - size.height / 2 + 40
        return NSPoint(x: x, y: y)
    }
}

// MARK: - View

struct TranscriptEditView: View {
    let initialText: String
    let vimEnabled: Bool
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    var onSaveToWorek: ((String) -> Void)? = nil
    var onTextChange: ((String) -> Void)?

    @State private var text: String
    @State private var mode: VimMode = .normal
    @State private var commandBuffer: String = ""

    init(initialText: String,
         vimEnabled: Bool,
         onCommit: @escaping (String) -> Void,
         onCancel: @escaping () -> Void,
         onSaveToWorek: ((String) -> Void)? = nil,
         onTextChange: ((String) -> Void)? = nil) {
        self.initialText = initialText
        self.vimEnabled = vimEnabled
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.onSaveToWorek = onSaveToWorek
        self.onTextChange = onTextChange
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            VimTextView(
                text: $text,
                vimEnabled: vimEnabled,
                onModeChange: { mode = $0 },
                onCommandBufferChange: { commandBuffer = $0 },
                onCommit: { onCommit(text) },
                onCancel: onCancel,
                onSaveToWorek: onSaveToWorek.map { save in { save(text) } }
            )
            Divider().opacity(0.4)
            hintBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.Border.tint, lineWidth: 0.5)
        )
        .onChange(of: text) { newText in
            onTextChange?(newText)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Edit Transcript")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if vimEnabled {
                Text(commandBuffer.isEmpty ? mode.label : commandBuffer)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(modeColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(modeColor.opacity(0.15))
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var modeColor: Color {
        switch mode {
        case .insert: return AppTheme.Status.success
        case .visual, .visualLine: return .orange
        case .commandLine, .search: return .purple
        case .normal: return .secondary
        }
    }

    // MARK: Hint bar

    private var hintBar: some View {
        HStack(spacing: 14) {
            if vimEnabled {
                switch mode {
                case .insert:
                    hint("ESC", "→ NORMAL")
                    hint("⌘↵", "Kopiuj")
                    if onSaveToWorek != nil { hint("⌥↵", "Worek") }
                case .commandLine, .search:
                    hint("↵", "Wykonaj")
                    hint("ESC", "Anuluj")
                default:
                    hint("i", "Pisz")
                    hint("hjkl", "Ruch")
                    hint("dd", "Usuń linię")
                    hint(":w ↵", "Kopiuj")
                    hint(":q ↵", "Anuluj")
                    if onSaveToWorek != nil { hint("⌥↵", "Worek") }
                }
            } else {
                Spacer()
                hint("⌘↵", "Kopiuj")
                if onSaveToWorek != nil { hint("⌥↵", "Worek") }
                hint("ESC", "Anuluj")
            }
            if vimEnabled { Spacer() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.Surface.control.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(AppTheme.Border.subtle, lineWidth: 0.5)
                        )
                )
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
}
