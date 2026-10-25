import SwiftUI

struct MiniRecorderView<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var assistantSession: AssistantSession
    let onRecordButtonTapped: () -> Void
    let onCloseTapped: () -> Void
    let onAssistantFollowUp: (String) -> Void
    @AppStorage(RecorderDisplaySettingsKeys.showLiveTranscript) private var showLiveTranscript = true
    @AppStorage("RecorderDestinationHUDEnabled") private var destinationHUDEnabled = true
    @ObservedObject private var messageCenter = RecorderStatusMessageCenter.shared
    @State private var showsFullConversation = false

    // MARK: - Layout Constants

    private let controlBarHeight: CGFloat = 40
    // Room for the Record label, mode name with time, waveform and mode icon.
    private let compactWidth: CGFloat = 344
    private let expandedWidth: CGFloat = 460
    private let assistantWidth: CGFloat = 460
    private let compactAssistantHeight: CGFloat = 220
    private let fullAssistantHeight: CGFloat = 320
    private let compactCornerRadius: CGFloat = 20
    private let expandedCornerRadius: CGFloat = 14
    // Room under the bar so its shadow isn't cut by the bottom of the host window.
    private let shadowClearance: CGFloat = 10

    // true when live transcript is streaming in during recording
    private var hasLiveTranscript: Bool {
        showLiveTranscript
            && stateProvider.recordingState == .recording
            && !stateProvider.partialTranscript.isEmpty
    }

    private var hasAssistantResponse: Bool {
        assistantSession.isVisible
    }

    private var shouldShowCloseButton: Bool {
        hasAssistantResponse &&
            stateProvider.recordingState == .idle &&
            !assistantSession.isBusy
    }

    // Show HUD strip while actively recording or when a status message is active.
    // A status message wins even when the HUD toggle is off or during transcribing/enhancing.
    private var shouldShowHUD: Bool {
        !hasAssistantResponse && (
            (destinationHUDEnabled && stateProvider.recordingState == .recording)
            || messageCenter.current != nil
        )
    }

    private var liveAssistantFollowUpText: String {
        guard showLiveTranscript, stateProvider.recordingState == .recording else { return "" }
        return stateProvider.partialTranscript
    }

    private var controlBar: some View {
        HStack(spacing: 0) {
            Group {
                if shouldShowCloseButton {
                    RecorderCloseButton(action: onCloseTapped)
                } else {
                    RecorderRecordButton(
                        recordingState: stateProvider.recordingState,
                        showsLabel: true,
                        action: onRecordButtonTapped
                    )
                }
            }
            .padding(.leading, 10)

            RecorderModeStatusLabel(
                recordingState: stateProvider.recordingState,
                startedAt: stateProvider.recordingStartedAt
            )
            .padding(.leading, 12)

            Spacer(minLength: 8)

            RecorderStatusDisplay(
                currentState: stateProvider.recordingState,
                audioMeter: recorder.audioMeter,
                showsProcessingText: false
            )

            Spacer(minLength: 0)

            RecorderModeButton(
                buttonSize: 22,
                padding: EdgeInsets()
            )
            .padding(.trailing, 12)
        }
        .frame(height: controlBarHeight)
    }

    private var transcriptSection: some View {
        VStack(spacing: 0) {
            if hasLiveTranscript {
                LiveTranscriptView(text: stateProvider.partialTranscript)
                PerforationRule()
            }
        }
    }

    // When the HUD is visible the panel must be at least expandedWidth so the
    // chips have room to render without truncation.
    private var currentWidth: CGFloat {
        if hasAssistantResponse { return assistantWidth }
        if hasLiveTranscript || shouldShowHUD { return expandedWidth }
        return compactWidth
    }

    private var currentCornerRadius: CGFloat {
        hasLiveTranscript || hasAssistantResponse || shouldShowHUD
            ? expandedCornerRadius
            : compactCornerRadius
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasAssistantResponse {
                AssistantPanelView(
                    session: assistantSession,
                    liveFollowUpText: liveAssistantFollowUpText,
                    showsFullConversation: $showsFullConversation,
                    height: showsFullConversation ? fullAssistantHeight : compactAssistantHeight,
                    onSend: onAssistantFollowUp
                )
                PerforationRule()
            } else {
                transcriptSection
            }
            controlBar
            if shouldShowHUD {
                PerforationRule()
                RecorderDestinationHUDView()
            }
        }
        .environment(\.recorderSurface, .panel)
        .frame(width: currentWidth)
        .background(AppTheme.Palette.paper)
        .clipShape(RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous)
                .strokeBorder(AppTheme.Palette.rule, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
        .padding(.bottom, shadowClearance)
        .animation(.easeInOut(duration: 0.3), value: hasLiveTranscript)
        .animation(.easeInOut(duration: 0.3), value: hasAssistantResponse)
        .animation(.easeInOut(duration: 0.3), value: shouldShowHUD)
        .animation(.easeInOut(duration: 0.25), value: showsFullConversation)
        .onChange(of: assistantSession.isVisible) {
            if !assistantSession.isVisible { showsFullConversation = false }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
