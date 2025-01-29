import Foundation

enum NetworkError: Error {
    case invalidURL
    case invalidResponse
    case networkError(Error)
    case decodingError
}

class NetworkManager {
    static let shared = NetworkManager()
    private init() {}
    
    func sendZkLoginProofRequest(token: String) async throws -> Data {
        guard let url = URL(string: Constants.zkLoginAPIEndpoint) else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ["token": token]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw NetworkError.invalidResponse
            }
            
            return data
        } catch {
            throw NetworkError.networkError(error)
        }
    }
} 