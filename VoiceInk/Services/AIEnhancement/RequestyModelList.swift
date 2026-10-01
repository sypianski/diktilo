import Foundation

/// Model list of the Requesty router (OpenAI-compatible `GET /v1/models`).
/// Ids carry the vendor prefix, e.g. `openai/gpt-4.1-mini`, `anthropic/claude-sonnet-4-5`.
/// See https://docs.requesty.ai/api-reference/endpoint/models-list
enum RequestyModelList {
    static let modelsURL = URL(string: "https://router.requesty.ai/v1/models")!

    enum FetchError: Error {
        case badStatus(Int)
        case unexpectedFormat
    }

    static func fetch(apiKey: String?, timeout: TimeInterval = 15) async throws -> [String] {
        var request = URLRequest(url: modelsURL, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.badStatus(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            throw FetchError.unexpectedFormat
        }

        return items.compactMap { $0["id"] as? String }.sorted()
    }
}
