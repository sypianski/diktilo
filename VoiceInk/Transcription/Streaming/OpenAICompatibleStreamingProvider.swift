import Foundation
import os

/// Streaming transcription provider for self-hosted OpenAI-compatible servers
/// that implement the OpenAI Realtime API (e.g. speaches `/v1/realtime`).
///
/// Protocol (validated against speaches):
/// - Connect: `ws(s)://<host>/v1/realtime?model=<model>` — the `model` query
///   parameter is required; without it the server rejects the handshake.
/// - After `session.created`, send `session.update` configuring
///   `input_audio_transcription` and `turn_detection` with
///   `create_response: false` (otherwise the server tries to run an LLM
///   conversation turn after every commit and errors out).
/// - Audio: base64 PCM16 mono at 24 kHz in `input_audio_buffer.append`.
///   VoiceInk's recorder emits 16 kHz, so chunks are upsampled 2:3 here.
/// - Server VAD auto-commits on speech pauses; each utterance arrives as
///   `conversation.item.input_audio_transcription.completed`. There are no
///   word-level partials — the live transcript grows utterance by utterance.
final class OpenAICompatibleStreamingProvider: StreamingTranscriptionProvider {

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "OpenAICompatibleStreamingProvider")
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?
    private var receiveTask: Task<Void, Never>?

    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>

    init() {
        var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        urlSession?.invalidateAndCancel()
        eventsContinuation?.finish()
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        guard let customModel = model as? CustomCloudModel else {
            throw StreamingTranscriptionError.connectionFailed("OpenAICompatibleStreamingProvider requires a custom cloud model")
        }

        guard let url = Self.realtimeURL(fromAPIEndpoint: customModel.apiEndpoint, modelName: customModel.modelName) else {
            throw StreamingTranscriptionError.connectionFailed("Cannot derive realtime URL from endpoint: \(customModel.apiEndpoint)")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let apiKey = customModel.apiKey
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        self.urlSession = session
        self.webSocketTask = task
        task.resume()

        // Handshake: the server greets with `session.created`.
        let greeting = try await task.receive()
        guard case .string(let greetingText) = greeting,
              let greetingData = greetingText.data(using: .utf8),
              let greetingJSON = try? JSONSerialization.jsonObject(with: greetingData) as? [String: Any],
              greetingJSON["type"] as? String == "session.created" else {
            throw StreamingTranscriptionError.connectionFailed("Expected session.created greeting from realtime endpoint")
        }

        // Configure transcription-only session. `turn_detection` must be a
        // complete object (all fields are required by the server's schema);
        // `prefix_padding_ms` triggers a benign "not supported" warning on
        // speaches but is required for the object to validate.
        var inputAudioTranscription: [String: Any] = ["model": customModel.modelName]
        if let language, language != "auto", !language.isEmpty {
            inputAudioTranscription["language"] = language
        }
        let sessionUpdate: [String: Any] = [
            "type": "session.update",
            "session": [
                "input_audio_transcription": inputAudioTranscription,
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 550,
                    "create_response": false,
                ],
            ],
        ]
        try await sendJSON(sessionUpdate)

        eventsContinuation?.yield(.sessionStarted)

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func sendAudioChunk(_ data: Data) async throws {
        let upsampled = Self.upsample16kTo24k(pcm16: data)
        let message: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": upsampled.base64EncodedString(),
        ]
        try await sendJSON(message)
    }

    func commit() async throws {
        try await sendJSON(["type": "input_audio_buffer.commit"])
    }

    func disconnect() async {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        eventsContinuation?.finish()
    }

    // MARK: - URL derivation

    /// Derives the realtime WebSocket URL from a batch transcription endpoint.
    /// `http(s)://host:port/v1/audio/transcriptions` → `ws(s)://host:port/v1/realtime?model=<model>`
    static func realtimeURL(fromAPIEndpoint endpoint: String, modelName: String) -> URL? {
        guard var components = URLComponents(string: endpoint) else { return nil }

        switch components.scheme {
        case "https": components.scheme = "wss"
        case "http": components.scheme = "ws"
        case "wss", "ws": break
        default: return nil
        }

        var path = components.path
        if let range = path.range(of: "/audio/transcriptions") {
            path = String(path[..<range.lowerBound])
        }
        if path.hasSuffix("/realtime") {
            // Already a realtime URL — keep as-is.
        } else if path.hasSuffix("/v1") || path.hasSuffix("/v1/") {
            path = path.hasSuffix("/") ? path + "realtime" : path + "/realtime"
        } else if path.isEmpty || path == "/" {
            path = "/v1/realtime"
        } else {
            path = path + "/realtime"
        }
        components.path = path
        components.queryItems = [URLQueryItem(name: "model", value: modelName)]
        return components.url
    }

    // MARK: - Audio

    /// Linear-interpolation upsample of 16-bit little-endian mono PCM from 16 kHz to 24 kHz (2:3).
    static func upsample16kTo24k(pcm16 data: Data) -> Data {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 1 else { return data }

        var input = [Int16](repeating: 0, count: sampleCount)
        data.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for index in 0..<sampleCount {
                input[index] = Int16(littleEndian: int16Buffer[index])
            }
        }

        let outputCount = sampleCount * 3 / 2
        var output = [Int16](repeating: 0, count: outputCount)
        for outIndex in 0..<outputCount {
            let sourcePosition = Double(outIndex) * 2.0 / 3.0
            let leftIndex = min(Int(sourcePosition), sampleCount - 1)
            let rightIndex = min(leftIndex + 1, sampleCount - 1)
            let fraction = sourcePosition - Double(leftIndex)
            let interpolated = Double(input[leftIndex]) * (1.0 - fraction) + Double(input[rightIndex]) * fraction
            output[outIndex] = Int16(max(Double(Int16.min), min(Double(Int16.max), interpolated.rounded())))
        }

        return output.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    // MARK: - Private

    private func sendJSON(_ object: [String: Any]) async throws {
        guard let task = webSocketTask else {
            throw StreamingTranscriptionError.notConnected
        }
        let jsonData = try JSONSerialization.data(withJSONObject: object)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw StreamingTranscriptionError.audioConversionFailed
        }
        try await task.send(.string(jsonString))
    }

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    eventsContinuation?.yield(.error(StreamingTranscriptionError.connectionFailed(error.localizedDescription)))
                }
                break
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "conversation.item.input_audio_transcription.completed":
            // Empty transcripts still matter: the final explicit commit often
            // covers trailing silence only, and its (empty) completion event is
            // what acknowledges the commit upstream.
            let transcript = (json["transcript"] as? String) ?? ""
            eventsContinuation?.yield(.committed(text: transcript))

        case "error":
            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? "Realtime server error"
            if message.contains("is not supported") {
                // Benign per-field warnings from session.update (e.g. prefix_padding_ms).
                logger.info("Ignoring unsupported-field warning: \(message, privacy: .public)")
            } else if message.contains("buffer too small") || message.contains("buffer is empty") {
                // Commit raced with a VAD auto-commit that already flushed the
                // buffer — everything is transcribed; acknowledge the commit.
                eventsContinuation?.yield(.committed(text: ""))
            } else {
                eventsContinuation?.yield(.error(StreamingTranscriptionError.serverError(message)))
            }

        default:
            // session.updated, input_audio_buffer.speech_started/stopped,
            // input_audio_buffer.committed, conversation.item.created — no-ops.
            break
        }
    }
}
