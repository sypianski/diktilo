import SwiftUI

// MARK: - Surface

/// Where the shared recorder controls are drawn. The notch panel keeps a
/// black body so it blends into the hardware notch, but draws on it with the
/// charcoal palette (warm ink, amber accents); the floating mini panel uses
/// the app palette (paper in light mode, charcoal in dark).
enum RecorderSurface {
    case notch
    case panel
}

private struct RecorderSurfaceKey: EnvironmentKey {
    static let defaultValue: RecorderSurface = .notch
}

extension EnvironmentValues {
    var recorderSurface: RecorderSurface {
        get { self[RecorderSurfaceKey.self] }
        set { self[RecorderSurfaceKey.self] = newValue }
    }
}

/// Colour roles for the recorder controls. On the notch each role takes the
/// opacity it always had, applied to the slot's warm ink instead of white.
struct RecorderPalette {
    let surface: RecorderSurface

    init(_ surface: RecorderSurface) {
        self.surface = surface
    }

    private var isPanel: Bool { surface == .panel }
    private typealias Slot = AppTheme.Palette.Slot

    func text(notch opacity: Double) -> Color {
        isPanel ? AppTheme.Palette.ink : Slot.ink.opacity(opacity)
    }

    func secondaryText(notch opacity: Double) -> Color {
        isPanel ? AppTheme.Palette.inkSecondary : Slot.ink.opacity(opacity)
    }

    func disabledText(notch opacity: Double) -> Color {
        isPanel ? AppTheme.Palette.inkSecondary.opacity(0.5) : Slot.ink.opacity(opacity)
    }

    func fill(notch opacity: Double) -> Color {
        isPanel ? AppTheme.Palette.chip : Slot.ink.opacity(opacity)
    }

    func subtleFill(notch opacity: Double) -> Color {
        isPanel ? AppTheme.Palette.chip.opacity(0.55) : Slot.ink.opacity(opacity)
    }

    func border(notch opacity: Double) -> Color {
        isPanel ? AppTheme.Palette.rule : Slot.ink.opacity(opacity)
    }

    func accent(notch opacity: Double) -> Color {
        isPanel ? AppTheme.Palette.amber : AppTheme.Palette.amber.opacity(opacity)
    }

    var onAccent: Color { AppTheme.Palette.onAmber }
    var waveform: Color { isPanel ? AppTheme.Palette.waveform : AppTheme.Palette.amber }
    /// Dashed divider between the recorder's bands.
    var rule: Color { isPanel ? AppTheme.Palette.rule : Slot.rule }
    /// Backdrop behind icon-only controls; the notch draws none.
    var controlFill: Color { isPanel ? AppTheme.Palette.chip : .clear }
}

// MARK: - Icon Toggle Button

struct RecorderToggleButton: View {
    let isEnabled: Bool
    let icon: String
    let disabled: Bool
    let action: () -> Void
    @Environment(\.recorderSurface) private var surface

    init(isEnabled: Bool, icon: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.icon = icon
        self.disabled = disabled
        self.action = action
    }

    private var isEmoji: Bool {
        !icon.contains(".") && !icon.contains("-") && icon.unicodeScalars.contains { !$0.isASCII }
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isEmoji {
                    Text(icon).font(.system(size: 14))
                } else {
                    Image(systemName: icon).font(.system(size: 13))
                }
            }
            .foregroundColor(glyphColor)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(disabled)
    }

    private var palette: RecorderPalette { RecorderPalette(surface) }

    private var glyphColor: Color {
        if disabled { return palette.disabledText(notch: 0.3) }
        return isEnabled ? palette.text(notch: 1) : palette.secondaryText(notch: 0.6)
    }
}

// MARK: - Record Button

struct RecorderRecordButton: View {
    let recordingState: RecordingState
    let action: () -> Void
    @Environment(\.recorderSurface) private var surface

    private var visualState: VisualState {
        switch recordingState {
        case .idle, .starting, .busy:
            return .ready
        case .recording:
            return .recording
        case .transcribing, .enhancing:
            return .processing
        }
    }

    private var isDisabled: Bool {
        switch recordingState {
        case .idle, .recording:
            return false
        case .starting, .transcribing, .enhancing, .busy:
            return true
        }
    }

    var body: some View {
        Button(action: action) {
            buttonFace
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(accessibilityLabel)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var buttonFace: some View {
        ZStack {
            Circle()
                .fill(colors.surface)
                .overlay(
                    Circle()
                        .strokeBorder(colors.border, lineWidth: colors.borderWidth)
                )

            stateMark
        }
        .frame(width: 21, height: 21)
        .contentShape(Circle())
        .animation(.easeOut(duration: 0.16), value: visualState)
    }

    private var colors: StateColors {
        surface == .panel ? panelColors : notchColors
    }

    private var notchColors: StateColors {
        switch visualState {
        case .ready:
            return StateColors(
                surface: AppTheme.Palette.Slot.chip,
                border: AppTheme.Palette.Slot.rule,
                mark: AppTheme.Palette.Slot.inkSecondary
            )
        case .recording:
            return StateColors(
                surface: AppTheme.Palette.amber,
                border: AppTheme.Palette.amber,
                mark: AppTheme.Palette.onAmber
            )
        case .processing:
            return StateColors(
                surface: AppTheme.Palette.Slot.chip,
                border: AppTheme.Palette.Slot.rule,
                mark: AppTheme.Palette.Slot.ink.opacity(0.86)
            )
        }
    }

    // Amber marks the live recording, like the icon's tile; idle and
    // processing sit back on the paper.
    private var panelColors: StateColors {
        switch visualState {
        case .ready, .processing:
            return StateColors(
                surface: AppTheme.Palette.chip,
                border: AppTheme.Palette.rule,
                mark: AppTheme.Palette.ink,
                borderWidth: 1
            )
        case .recording:
            return StateColors(
                surface: AppTheme.Palette.amber,
                border: AppTheme.Palette.ink,
                mark: AppTheme.Palette.onAmber,
                borderWidth: 1.5
            )
        }
    }

    @ViewBuilder
    private var stateMark: some View {
        switch visualState {
        case .ready, .recording:
            RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                .fill(colors.mark)
                .frame(width: 8, height: 8)
        case .processing:
            ProcessingIndicator(color: colors.mark)
        }
    }

    private var accessibilityLabel: String {
        switch recordingState {
        case .idle:
            return String(localized: "Start recording")
        case .starting:
            return String(localized: "Starting recording")
        case .recording:
            return String(localized: "Stop recording")
        case .transcribing:
            return String(localized: "Transcribing recording")
        case .enhancing:
            return String(localized: "Enhancing recording")
        case .busy:
            return String(localized: "Recorder unavailable")
        }
    }

    private enum VisualState: Equatable {
        case ready
        case recording
        case processing
    }

    private struct StateColors {
        let surface: Color
        let border: Color
        let mark: Color
        var borderWidth: CGFloat = 0.6
    }
}

// MARK: - Close Button

struct RecorderCloseButton: View {
    let action: () -> Void
    @Environment(\.recorderSurface) private var surface

    private var palette: RecorderPalette { RecorderPalette(surface) }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(palette.fill(notch: 0.13))
                    .overlay(
                        Circle()
                            .strokeBorder(palette.border(notch: 0.18), lineWidth: 0.6)
                    )

                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(palette.text(notch: 0.86))
            }
            .frame(width: 21, height: 21)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close")
    }
}

// MARK: - Processing Indicator

struct ProcessingIndicator: View {
    @State private var rotation: Double = 0
    let color: Color

    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.9)
            .stroke(color, lineWidth: 1.5)
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Progress Dot Animation

struct ProgressAnimation: View {
    let color: Color
    let animationSpeed: Double

    private let dotCount = 5
    private let dotSize: CGFloat = 3
    private let dotSpacing: CGFloat = 2

    @State private var currentDot = 0
    @State private var timer: Timer?

    init(color: Color = .white, animationSpeed: Double = 0.3) {
        self.color = color
        self.animationSpeed = animationSpeed
    }

    var body: some View {
        HStack(spacing: dotSpacing) {
            ForEach(0..<dotCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: dotSize / 2)
                    .fill(color.opacity(index <= currentDot ? 0.85 : 0.25))
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .onAppear { startAnimation() }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func startAnimation() {
        timer?.invalidate()
        currentDot = 0
        timer = Timer.scheduledTimer(withTimeInterval: animationSpeed, repeats: true) { _ in
            currentDot = (currentDot + 1) % (dotCount + 2)
            if currentDot > dotCount { currentDot = -1 }
        }
    }
}

// MARK: - Mode Button

struct RecorderModeButton: View {
    @ObservedObject private var modeManager = OutputProfileManager.shared
    let buttonSize: CGFloat
    let padding: EdgeInsets

    @State private var isPopoverPresented = false
    @State private var isHoveringButton: Bool = false
    @State private var isHoveringPopover: Bool = false
    @State private var dismissWorkItem: DispatchWorkItem?
    @Environment(\.recorderSurface) private var surface

    init(buttonSize: CGFloat = 28, padding: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 7)) {
        self.buttonSize = buttonSize
        self.padding = padding
    }

    var body: some View {
        RecorderToggleButton(
            isEnabled: !modeManager.enabledConfigurations.isEmpty,
            icon: modeManager.enabledConfigurations.isEmpty ? "square.grid.2x2" : (modeManager.currentEffectiveConfiguration?.icon.value ?? "square.grid.2x2"),
            disabled: modeManager.enabledConfigurations.isEmpty
        ) {
            isPopoverPresented.toggle()
        }
        .frame(width: buttonSize)
        .background(
            Circle()
                .fill(RecorderPalette(surface).controlFill)
                .frame(width: buttonSize, height: buttonSize)
        )
        .padding(padding)
        .onHover {
            isHoveringButton = $0
            syncPopoverVisibility()
        }
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            OutputProfilePopover()
                .onHover {
                    isHoveringPopover = $0
                    syncPopoverVisibility()
                }
        }
    }

    private func syncPopoverVisibility() {
        if isHoveringButton || isHoveringPopover {
            dismissWorkItem?.cancel()
            dismissWorkItem = nil
            isPopoverPresented = true
        } else {
            dismissWorkItem?.cancel()
            let work = DispatchWorkItem { [isPopoverPresentedBinding = $isPopoverPresented] in
                isPopoverPresentedBinding.wrappedValue = false
            }
            dismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
}

// MARK: - Live Transcript View

private struct TranscriptHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct LiveTranscriptView: View {
    let text: String
    @Environment(\.recorderSurface) private var surface

    // Grow with the spoken text (panel is bottom-anchored, so height grows
    // upward) up to a cap, then scroll. Keeps early lines visible instead of
    // scrolling them out of a fixed-height window.
    private let minHeight: CGFloat = 30
    private let maxHeight: CGFloat = 220
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(RecorderPalette(surface).text(notch: 0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: TranscriptHeightKey.self, value: geo.size.height)
                        }
                    )
                    .id("bottom")
            }
            .frame(height: min(max(contentHeight, minHeight), maxHeight))
            .onPreferenceChange(TranscriptHeightKey.self) { newValue in
                contentHeight = newValue
            }
            .mask(
                contentHeight > maxHeight
                    ? AnyView(LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.14),
                            .init(color: .black, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    : AnyView(Color.black)
            )
            .onChange(of: text) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        .transaction { $0.disablesAnimations = true }
    }
}

// MARK: - Recorder Status Display

struct RecorderStatusDisplay: View {
    let currentState: RecordingState
    let audioMeter: AudioMeter
    let menuBarHeight: CGFloat?
    @Environment(\.recorderSurface) private var surface

    init(currentState: RecordingState, audioMeter: AudioMeter, menuBarHeight: CGFloat? = nil) {
        self.currentState = currentState
        self.audioMeter = audioMeter
        self.menuBarHeight = menuBarHeight
    }

    var body: some View {
        let palette = RecorderPalette(surface)
        Group {
            if currentState == .enhancing {
                ProcessingStatusDisplay(mode: .enhancing, color: palette.text(notch: 1)).transition(.opacity)
            } else if currentState == .transcribing {
                ProcessingStatusDisplay(mode: .transcribing, color: palette.text(notch: 1)).transition(.opacity)
            } else if currentState == .recording {
                AudioVisualizer(audioMeter: audioMeter, color: palette.waveform, isActive: true)
                    .scaleEffect(y: menuBarHeight != nil ? min(1.0, (menuBarHeight! - 8) / 25) : 1.0, anchor: .center)
                    .transition(.opacity)
            } else {
                StaticVisualizer(color: palette.waveform)
                    .scaleEffect(y: menuBarHeight != nil ? min(1.0, (menuBarHeight! - 8) / 25) : 1.0, anchor: .center)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentState)
    }
}

// MARK: - Assistant Response Panel

struct AssistantPanelView: View {
    @ObservedObject var session: AssistantSession
    let liveFollowUpText: String
    let onSend: (String) -> Void

    @State private var draftMessage = ""
    @FocusState private var isFollowUpFieldFocused: Bool
    @Environment(\.recorderSurface) private var surface

    private let horizontalPadding: CGFloat = 20

    private var palette: RecorderPalette { RecorderPalette(surface) }
    private var followUpTextColor: Color { palette.text(notch: 0.9) }

    private var statusText: String? {
        switch session.phase {
        case .responding, .sendingFollowUp:
            return String(localized: "Thinking")
        case .failed(let message):
            return message
        case .inactive, .ready:
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            messageList
            followUpRow
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 10)
        .frame(height: 320)
        .onAppear(perform: focusFollowUpFieldIfAvailable)
        .onChange(of: session.phase) {
            focusFollowUpFieldIfAvailable()
        }
    }

    private var fullConversationText: String {
        session.messages.map { msg in
            let prefix = msg.role == .user ? "You" : "Assistant"
            return "\(prefix): \(msg.content)"
        }.joined(separator: "\n\n")
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(session.messages) { message in
                        AssistantMessageBubble(message: message)
                            .id(message.id)
                    }

                    if let statusText {
                        Text(statusText)
                            .font(.system(size: 11))
                            .foregroundColor(palette.secondaryText(notch: 0.62))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("status")
                    }
                }
                .padding(.vertical, 2)
                .overlay(alignment: .topLeading) {
                    if !session.messages.isEmpty {
                        CopyIconButton(textToCopy: fullConversationText)
                            .scaleEffect(0.72)
                    }
                }
            }
            .onChange(of: session.messages.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: session.phase) {
                scrollToBottom(proxy)
            }
        }
    }

    private var followUpRow: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                if shouldShowLiveFollowUpText {
                    Text(liveFollowUpText)
                        .font(.system(size: 12))
                        .foregroundStyle(followUpTextColor)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .allowsHitTesting(false)
                }

                TextField("", text: $draftMessage)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(followUpTextColor)
                    .tint(followUpTextColor)
                    .disabled(!session.canSendFollowUp)
                    .focused($isFollowUpFieldFocused)
                    .onSubmit(sendDraftMessage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(palette.fill(notch: 0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(action: sendDraftMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(canSendDraft ? palette.onAccent : palette.disabledText(notch: 0.35))
                    .frame(width: 24, height: 24)
                    .background(canSendDraft ? palette.accent(notch: 0.88) : palette.fill(notch: 0.10))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSendDraft)
            .help("Send follow up")
        }
    }

    private var shouldShowLiveFollowUpText: Bool {
        draftMessage.isEmpty &&
            !liveFollowUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSendDraft: Bool {
        session.canSendFollowUp &&
            !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraftMessage() {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard session.canSendFollowUp, !trimmed.isEmpty else { return }
        draftMessage = ""
        onSend(trimmed)
        focusFollowUpFieldIfAvailable()
    }

    private func focusFollowUpFieldIfAvailable() {
        guard session.canSendFollowUp else { return }
        DispatchQueue.main.async {
            isFollowUpFieldFocused = true
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                if let last = session.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                } else {
                    proxy.scrollTo("status", anchor: .bottom)
                }
            }
        }
    }
}

private struct AssistantMessageBubble: View {
    let message: AssistantDisplayMessage
    @Environment(\.recorderSurface) private var surface

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        let palette = RecorderPalette(surface)
        HStack {
            if isUser {
                Spacer(minLength: 36)
            }

            MarkdownContentView(
                message.content,
                fontSize: 12,
                foregroundColor: palette.text(notch: isUser ? 0.92 : 0.86),
                alignment: .leading
            )
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isUser ? palette.fill(notch: 0.16) : palette.subtleFill(notch: 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if !isUser {
                        CopyIconButton(textToCopy: message.content)
                            .scaleEffect(0.72)
                            .padding(0)
                    }
                }
                .help(isUser ? message.content : "")

            if !isUser {
                Spacer(minLength: 36)
            }
        }
    }
}
