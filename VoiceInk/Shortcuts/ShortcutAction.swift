import Foundation

enum ShortcutAction: Hashable {
    case primaryRecording
    case secondaryRecording
    case pasteLastTranscription
    case pasteLastEnhancement
    case retryLastTranscription
    case cancelRecorder
    case openHistoryWindow
    case quickAddToDictionary
    case openVimEditor
    case openWorek
    case profile(UUID)
    case finishWithCopy
    case finishWithPaste
    case finishWithEditWindow
    case finishWithSaveTarget(UUID)
    case recorderPanelEscape
    case recorderPanelMode(Int)
    case recorderPanelFinish

    var userDefaultsKey: String {
        "Shortcut_\(storageName)"
    }

    var isStored: Bool {
        switch self {
        case .recorderPanelEscape, .recorderPanelMode, .recorderPanelFinish:
            return false
        default:
            return true
        }
    }

    var storageName: String {
        switch self {
        case .primaryRecording:
            return "primaryRecording"
        case .secondaryRecording:
            return "secondaryRecording"
        case .pasteLastTranscription:
            return "pasteLastTranscription"
        case .pasteLastEnhancement:
            return "pasteLastEnhancement"
        case .retryLastTranscription:
            return "retryLastTranscription"
        case .cancelRecorder:
            return "cancelRecorder"
        case .openHistoryWindow:
            return "openHistoryWindow"
        case .quickAddToDictionary:
            return "quickAddToDictionary"
        case .openVimEditor:
            return "openVimEditor"
        case .openWorek:
            return "openWorek"
        case .profile(let id):
            return "mode_\(id.uuidString)"
        case .finishWithCopy:
            return "finishWithCopy"
        case .finishWithPaste:
            return "finishWithPaste"
        case .finishWithEditWindow:
            return "finishWithEditWindow"
        case .finishWithSaveTarget(let id):
            return "finishSaveTarget_\(id.uuidString)"
        case .recorderPanelEscape:
            return "recorderPanelEscape"
        case .recorderPanelMode(let index):
            return "recorderPanelMode_\(index)"
        case .recorderPanelFinish:
            return "recorderPanelFinish"
        }
    }

    var displayName: String {
        switch self {
        case .primaryRecording:
            return String(localized: "Primary Shortcut")
        case .secondaryRecording:
            return String(localized: "Secondary Shortcut")
        case .pasteLastTranscription:
            return String(localized: "Paste Last Transcription")
        case .pasteLastEnhancement:
            return String(localized: "Paste Last Enhanced Transcription")
        case .retryLastTranscription:
            return String(localized: "Retry Last Transcription")
        case .cancelRecorder:
            return String(localized: "Cancel Recording")
        case .openHistoryWindow:
            return String(localized: "Open History Window")
        case .quickAddToDictionary:
            return String(localized: "Quick Add to Dictionary")
        case .openVimEditor:
            return String(localized: "Open Vim Editor")
        case .openWorek:
            return String(localized: "Open Sako")
        case .profile(let id):
            if let config = OutputProfileManager.shared.getConfiguration(with: id) {
                return String(format: String(localized: "%@ Mode"), config.name)
            }

            if let template = StarterModeCatalog.templates.first(where: { $0.id == id }) {
                return String(format: String(localized: "%@ Mode"), template.name)
            }

            return String(localized: "Mode")
        case .finishWithCopy:
            return String(localized: "Finish → Copy")
        case .finishWithPaste:
            return String(localized: "Finish → Paste")
        case .finishWithEditWindow:
            return String(localized: "Finish → Edit Window")
        case .finishWithSaveTarget(let id):
            if let target = SaveTargetManager.shared.target(withID: id) {
                return String(format: String(localized: "Finish → %@"), target.name)
            }
            return String(localized: "Finish → Save Target")
        case .recorderPanelEscape:
            return String(localized: "Recorder Cancel")
        case .recorderPanelMode(let index):
            return String(format: String(localized: "Select Mode %@"), Self.displayNumber(forRecorderPanelIndex: index))
        case .recorderPanelFinish:
            return String(localized: "Finish Recording")
        }
    }

    static let globalUtilityActions: [Self] = [
        .pasteLastTranscription,
        .pasteLastEnhancement,
        .retryLastTranscription,
        .openHistoryWindow,
        .quickAddToDictionary,
        .openVimEditor,
        .openWorek
    ]

    static let recorderPanelStoredActions: [Self] = [
        .cancelRecorder
    ]

    /// One-shot "finish with …" destination actions with fixed identity
    /// (save-target variants are enumerated dynamically from the target list).
    static let finishDestinationActions: [Self] = [
        .finishWithCopy,
        .finishWithPaste,
        .finishWithEditWindow
    ]

    static let legacyKeyboardShortcutActions: [Self] = [
        .primaryRecording,
        .secondaryRecording,
        .pasteLastTranscription,
        .pasteLastEnhancement,
        .retryLastTranscription,
        .cancelRecorder,
        .openHistoryWindow,
        .quickAddToDictionary
    ]

    private static func displayNumber(forRecorderPanelIndex index: Int) -> String {
        index == 9 ? "10" : "\(index + 1)"
    }
}
