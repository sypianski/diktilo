import SwiftUI
import AppKit

private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct NotchRecorderView<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var assistantSession: AssistantSession
    let onRecordButtonTapped: () -> Void
    let onCloseTapped: () -> Void
    let onAssistantFollowUp: (String) -> Void
    @AppStorage(RecorderDisplaySettingsKeys.showLiveTranscript) private var showLiveTranscript = true
    @AppStorage("RecorderDestinationHUDEnabled") private var destinationHUDEnabled = true
    @ObservedObject private var messageCenter = RecorderStatusMessageCenter.shared

    // MARK: - Display State

    private enum DisplayState: Equatable {
        case collapsed
        case active
        case liveText
        case assistant
    }

    private var displayState: DisplayState {
        if assistantSession.isVisible {
            return .assistant
        }

        switch stateProvider.recordingState {
        case .recording:
            let shouldShowLive = showLiveTranscript && !stateProvider.partialTranscript.isEmpty
            return shouldShowLive ? .liveText : .active
        case .transcribing, .enhancing:
            return .active
        default:
            return .collapsed
        }
    }

    // MARK: - Screen Geometry

    private var notchWidth: CGFloat {
        guard let screen = NotchRecorderPanel.targetScreen ?? NSScreen.main else { return 180 }
        if let left = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width {
            return screen.frame.width - left - right
        }
        return 180
    }

    private var notchHeight: CGFloat {
        guard let screen = NotchRecorderPanel.targetScreen ?? NSScreen.main else { return 37 }
        if screen.safeAreaInsets.top > 0 { return screen.safeAreaInsets.top }
        return NSApplication.shared.mainMenu?.menuBarHeight ?? NSStatusBar.system.thickness
    }

    // MARK: - Layout Constants

    // Each side holds the visualizer (73 pt), spacing and the mode button
    // (20 pt) plus the edge padding; narrower sides spill the mode icon past
    // the pill's edge.
    private let recordingSideExpansion: CGFloat = 124
    private let transcriptSideExpansion: CGFloat = 124
    private let assistantSideExpansion: CGFloat = 230
    private let activeHeightBonus: CGFloat = 6
    private let transcriptPanelHeight: CGFloat = 57
    private let assistantPanelHeight: CGFloat = 320
    // The band plus the perforated rule above it; less clips the chips.
    private let hudPanelHeight: CGFloat = RecorderHUDMetrics.bandHeight + 1.5
    /// Least clear space between content and the pill's visible edge.
    private let edgeGutter: CGFloat = 10

    private var mainRowHeight: CGFloat { notchHeight + activeHeightBonus }

    // HUD strip appears only while actively recording (finish-destination
    // shortcuts are meaningful then), OR whenever a status message is active.
    // A status message wins even when the HUD toggle is off. Matches
    // MiniRecorderView: .active also covers .transcribing/.enhancing, so gate
    // the hint on the raw recording state, not displayState.
    private var shouldShowHUD: Bool {
        let hasMsg = messageCenter.current != nil
        let inNonAssistantState = displayState != .assistant && displayState != .liveText
        return inNonAssistantState && (
            (destinationHUDEnabled && stateProvider.recordingState == .recording)
            || hasMsg
        )
    }

    // MARK: - Pill Dimensions

    private var pillWidth: CGFloat {
        switch displayState {
        case .collapsed: return notchWidth
        case .active:    return notchWidth + recordingSideExpansion * 2
        case .liveText:  return notchWidth + transcriptSideExpansion * 2
        case .assistant: return notchWidth + assistantSideExpansion * 2
        }
    }

    private var pillHeight: CGFloat {
        let base: CGFloat
        switch displayState {
        case .collapsed: return 0
        case .active:    base = mainRowHeight
        case .liveText:  return mainRowHeight + transcriptPanelHeight
        case .assistant: return mainRowHeight + assistantPanelHeight
        }
        return base + (shouldShowHUD ? hudPanelHeight : 0)
    }

    private var sideExpansion: CGFloat {
        switch displayState {
        case .liveText:
            return transcriptSideExpansion
        case .assistant:
            return assistantSideExpansion
        case .active, .collapsed:
            return recordingSideExpansion
        }
    }

    // NotchShape draws its sides `topCornerRadius` in from the frame (the
    // outer strip is only the flare meeting the menu bar), so edge padding
    // is measured from there.
    private var topCornerRadius: CGFloat {
        displayState == .liveText ? 12 : 8
    }

    private var bottomCornerRadius: CGFloat {
        displayState == .liveText || displayState == .assistant || shouldShowHUD ? 22 : 16
    }

    private var sideEdgePadding: CGFloat {
        topCornerRadius + edgeGutter
    }

    private var shouldShowCloseButton: Bool {
        displayState == .assistant &&
            stateProvider.recordingState == .idle &&
            !assistantSession.isBusy
    }

    private var liveAssistantFollowUpText: String {
        guard showLiveTranscript, stateProvider.recordingState == .recording else { return "" }
        return stateProvider.partialTranscript
    }

    // MARK: - Animation

    private let expandAnimation = Animation.spring(response: 0.42, dampingFraction: 0.80)
    private let collapseAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0)

    private var pillAnimation: Animation {
        displayState == .collapsed ? collapseAnimation : expandAnimation
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            pill.position(x: geo.size.width / 2, y: pillHeight / 2)
        }
        .animation(pillAnimation, value: displayState)
        .animation(expandAnimation, value: shouldShowHUD)
    }

    // MARK: - Pill

    private var pill: some View {
        VStack(spacing: 0) {
            mainRow
            hudPanel
            liveTextPanel
            assistantPanel
        }
        .frame(width: pillWidth, height: pillHeight)
        .background(
            ZStack {
                VisualEffectBlur()
                Color.black.opacity(0.72)
            }
        )
        .clipShape(
            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
        )
    }

    // MARK: - Destination HUD Panel

    private var hudPanel: some View {
        VStack(spacing: 0) {
            if shouldShowHUD {
                PerforationRule(color: AppTheme.Palette.Slot.rule)
                RecorderDestinationHUDView()
                    .padding(.horizontal, sideEdgePadding)
            }
        }
        .frame(height: shouldShowHUD ? hudPanelHeight : 0)
        .clipped()
        .animation(expandAnimation, value: shouldShowHUD)
    }

    // MARK: - Main Row

    private var mainRow: some View {
        ZStack {
            Color.clear

            HStack(spacing: 14) {
                if shouldShowCloseButton {
                    RecorderCloseButton(action: onCloseTapped)
                } else {
                    RecorderRecordButton(
                        recordingState: stateProvider.recordingState,
                        action: onRecordButtonTapped
                    )
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, sideEdgePadding)
            .frame(width: sideExpansion, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(displayState != .collapsed ? 1 : 0)
            .animation(
                displayState != .collapsed ? expandAnimation.delay(0.09) : collapseAnimation,
                value: displayState
            )

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                RecorderStatusDisplay(
                    currentState: stateProvider.recordingState,
                    audioMeter: recorder.audioMeter,
                    menuBarHeight: notchHeight
                )
                RecorderModeButton(buttonSize: 20, padding: EdgeInsets())
            }
            .padding(.trailing, sideEdgePadding)
            // Trailing alignment: if the content ever outgrows the side, it
            // spills under the hardware notch, never past the pill's edge.
            .frame(width: sideExpansion, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(displayState != .collapsed ? 1 : 0)
            .animation(
                displayState != .collapsed ? expandAnimation.delay(0.09) : collapseAnimation,
                value: displayState
            )
        }
        .frame(height: mainRowHeight)
    }

    // MARK: - Live Text Panel

    private var liveTextPanel: some View {
        VStack(spacing: 0) {
            if displayState == .liveText {
                PerforationRule(color: AppTheme.Palette.Slot.rule)
                LiveTranscriptView(
                    text: stateProvider.partialTranscript,
                    maxHeight: transcriptPanelHeight - 1.5
                )
                .padding(.horizontal, 8)
            }
        }
        .frame(height: displayState == .liveText ? transcriptPanelHeight : 0)
        .clipped()
    }

    private var assistantPanel: some View {
        VStack(spacing: 0) {
            if displayState == .assistant {
                PerforationRule(color: AppTheme.Palette.Slot.rule)
                AssistantPanelView(
                    session: assistantSession,
                    liveFollowUpText: liveAssistantFollowUpText,
                    onSend: onAssistantFollowUp
                )
            }
        }
        .frame(height: displayState == .assistant ? assistantPanelHeight : 0)
        .clipped()
    }
}
