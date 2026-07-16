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
        guard let screen = NSScreen.main else { return 180 }
        if let left = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width {
            return screen.frame.width - left - right
        }
        return 180
    }

    private var notchHeight: CGFloat {
        guard let screen = NSScreen.main else { return 37 }
        if screen.safeAreaInsets.top > 0 { return screen.safeAreaInsets.top }
        return NSApplication.shared.mainMenu?.menuBarHeight ?? NSStatusBar.system.thickness
    }

    // MARK: - Layout Constants

    private let recordingSideExpansion: CGFloat = 90
    private let transcriptSideExpansion: CGFloat = 110
    private let assistantSideExpansion: CGFloat = 230
    private let activeHeightBonus: CGFloat = 6
    private let transcriptPanelHeight: CGFloat = 57
    private let assistantPanelHeight: CGFloat = 320
    private let hudPanelHeight: CGFloat = 28

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

    private var sideEdgePadding: CGFloat {
        displayState == .liveText || displayState == .assistant ? 20 : 16
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
                topCornerRadius: displayState == .liveText ? 12 : 8,
                bottomCornerRadius: displayState == .liveText || displayState == .assistant || shouldShowHUD ? 22 : 16
            )
        )
    }

    // MARK: - Destination HUD Panel

    private var hudPanel: some View {
        VStack(spacing: 0) {
            if shouldShowHUD {
                Divider().background(Color.white.opacity(0.10))
                RecorderDestinationHUDView()
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
            .frame(width: sideExpansion)
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
            .frame(width: sideExpansion)
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
                Divider().background(Color.white.opacity(0.15))
                LiveTranscriptView(text: stateProvider.partialTranscript)
                    .padding(.horizontal, 8)
            }
        }
        .frame(height: displayState == .liveText ? transcriptPanelHeight : 0)
        .clipped()
    }

    private var assistantPanel: some View {
        VStack(spacing: 0) {
            if displayState == .assistant {
                Divider().background(Color.white.opacity(0.15))
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
