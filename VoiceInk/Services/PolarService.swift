import Foundation

class PolarService {
    private let organizationId = "Org"
    private let apiToken = "Polar"
    private let baseURL = "https://api.polar.sh"
    
    struct LicenseValidationResponse: Codable {
        let status: String
    }
    
    func validateLicenseKey(_ key: String) async throws -> Bool {
        let url = URL(string: "\(baseURL)/v1/users/license-keys/validate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        
        let body: [String: String] = [
            "key": key,
            "organization_id": organizationId
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, httpResponse) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = httpResponse as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            print("HTTP Status Code: \(httpResponse.statusCode)")
            if let errorString = String(data: data, encoding: .utf8) {
                print("Error Response: \(errorString)")
            }
        }
        
        let validationResponse = try JSONDecoder().decode(LicenseValidationResponse.self, from: data)
        return validationResponse.status == "granted"
    }
} 
