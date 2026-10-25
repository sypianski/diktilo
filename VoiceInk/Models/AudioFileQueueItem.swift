import AVFoundation
import Foundation

/// Represents a single audio file in the transcription queue.
enum QueueItemStatus: Equatable {
    case pending
    case processing(phase: ProcessingPhase)
    case completed
    case failed(message: String)

    enum ProcessingPhase: String {
        case loading = "Loading model..."
        case processingAudio = "Processing audio..."
        case transcribing = "Transcribing..."
        case enhancing = "Enhancing..."
    }

    /// 1-based position among the four processing steps.
    var stepNumber: Int? {
        guard case .processing(let phase) = self else { return nil }
        switch phase {
        case .loading: return 1
        case .processingAudio: return 2
        case .transcribing: return 3
        case .enhancing: return 4
        }
    }

    static let stepCount = 4

    var isTerminal: Bool {
        switch self {
        case .completed, .failed: return true
        default: return false
        }
    }
}

@MainActor
class AudioFileQueueItem: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let filename: String

    @Published var status: QueueItemStatus = .pending
    @Published var transcription: Transcription?
    /// Read when the file is added, so the queue can show length and size before processing.
    @Published var fileSize: Int64?
    @Published var duration: TimeInterval?

    init(url: URL) {
        self.url = url
        self.filename = url.lastPathComponent
        self.fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
    }
}

/// A file that was dropped or chosen but not queued, with the reason.
struct SkippedQueueFile: Identifiable {
    enum Reason {
        case unsupportedFormat
        case alreadyQueued
        case missing
    }

    let id = UUID()
    let filename: String
    let reason: Reason
}
