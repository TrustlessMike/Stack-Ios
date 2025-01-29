import Foundation
import Network

class NetworkManager {
    static let shared = NetworkManager()
    private let session: URLSession
    private let monitor = NWPathMonitor()
    private var isConnected = false
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var currentEphemeralKey: EphemeralKey?
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        
        session = URLSession(configuration: config)
        
        // Start monitoring network connectivity
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
            print("Network status: \(path.status == .satisfied ? "Connected" : "Disconnected")")
            let interfaces = path.availableInterfaces
            if !interfaces.isEmpty {
                print("Available interfaces: \(interfaces.map { $0.name })")
            } else {
                print("No network interfaces available")
            }
            
            if path.status == .satisfied {
                self?.connectionContinuation?.resume(returning: ())
                self?.connectionContinuation = nil
            } else {
                self?.connectionContinuation?.resume(throwing: NetworkError.noConnection)
                self?.connectionContinuation = nil
            }
        }
        monitor.start(queue: DispatchQueue.global())
    }
    
    private func waitForConnection() async throws {
        if isConnected { return }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.connectionContinuation = continuation
        }
    }
    
    private func decodeJWT(_ token: String) throws -> JWTPayload {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3,
              let payloadData = Data(base64Encoded: parts[1].padding(toLength: ((parts[1].count + 3) / 4) * 4, withPad: "=", startingAt: 0)) else {
            throw NetworkError.invalidResponse
        }
        return try JSONDecoder().decode(JWTPayload.self, from: payloadData)
    }
    
    func sendZkLoginProofRequest(token: String) async throws -> Data {
        // Wait for network connection
        try await waitForConnection()
        
        // Decode the JWT first
        let jwtPayload = try decodeJWT(token)
        guard let sub = jwtPayload.sub, let aud = jwtPayload.aud else {
            throw NetworkError.invalidResponse
        }
        
        // Step 1: Get the current epoch using RPC
        guard let systemStateURL = URL(string: Constants.rpcEndpoint) else {
            print("Invalid RPC URL: \(Constants.rpcEndpoint)")
            throw NetworkError.invalidURL
        }
        
        print("Fetching system state from: \(systemStateURL.absoluteString)")
        
        var systemStateRequest = URLRequest(url: systemStateURL)
        systemStateRequest.httpMethod = "POST"
        systemStateRequest.timeoutInterval = Constants.networkTimeout
        systemStateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        systemStateRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Proper JSON-RPC request
        let rpcRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "suix_getLatestSuiSystemState",
            "id": 1,
            "params": []
        ]
        
        systemStateRequest.httpBody = try JSONSerialization.data(withJSONObject: rpcRequest)
        print("System state request body: \(String(data: systemStateRequest.httpBody!, encoding: .utf8) ?? "")")
        
        let (systemStateData, systemStateResponse) = try await session.data(for: systemStateRequest)
        
        guard let httpResponse = systemStateResponse as? HTTPURLResponse else {
            print("Invalid system state response type")
            throw NetworkError.invalidResponse
        }
        
        print("System state response status code: \(httpResponse.statusCode)")
        if let responseString = String(data: systemStateData, encoding: .utf8) {
            print("System state response: \(responseString)")
        }
        
        if httpResponse.statusCode != 200 {
            throw NetworkError.serverError(statusCode: httpResponse.statusCode)
        }
        
        // Parse the RPC response
        guard let json = try JSONSerialization.jsonObject(with: systemStateData) as? [String: Any],
              let result = json["result"] as? [String: Any] else {
            print("Invalid JSON-RPC response format")
            if let responseString = String(data: systemStateData, encoding: .utf8) {
                print("Raw response: \(responseString)")
            }
            throw NetworkError.invalidResponse
        }
        
        // Debug print the result structure
        print("Result structure: \(result)")
        
        // Try to find epoch in the response structure
        let epoch: Int
        if let directEpoch = result["epoch"] as? Int {
            epoch = directEpoch
        } else if let epochString = result["epoch"] as? String,
                  let epochInt = Int(epochString) {
            epoch = epochInt
        } else if let systemState = result["systemState"] as? [String: Any],
                  let epochNumber = systemState["epoch"] as? Int {
            epoch = epochNumber
        } else if let systemStateData = result["data"] as? [String: Any],
                  let epochNumber = systemStateData["epoch"] as? Int {
            epoch = epochNumber
        } else {
            print("Could not find epoch in response structure")
            print("Available keys in result: \(result.keys.joined(separator: ", "))")
            if let epochValue = result["epoch"] {
                print("Found epoch value but of unexpected type: \(type(of: epochValue))")
                print("Epoch value: \(epochValue)")
            }
            throw NetworkError.invalidResponse
        }
        
        let maxEpoch = epoch + Constants.ephemeralKeyValidityInEpochs
        
        // Create new ephemeral key pair after getting epoch
        currentEphemeralKey = EphemeralKey(validUntilEpoch: maxEpoch)
        
        // Convert public key to bytes for the nonce request
        let publicKeyData = currentEphemeralKey?.publicKey.rawRepresentation
        let publicKeyHex = publicKeyData?.map { String(format: "%02x", $0) }.joined() ?? ""
        
        // Step 2: Get the proof from the zkLogin service
        guard let proofURL = URL(string: "\(Constants.zkLoginAPIEndpoint)/prove") else {
            print("Invalid proof URL: \(Constants.zkLoginAPIEndpoint)/prove")
            throw NetworkError.invalidURL
        }
        
        print("Fetching proof from: \(proofURL.absoluteString)")
        
        var proofRequest = URLRequest(url: proofURL)
        proofRequest.httpMethod = "POST"
        proofRequest.timeoutInterval = Constants.networkTimeout
        proofRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        proofRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Generate random bytes for the proof request
        let randomBytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let jwtRandomness = "0x" + randomBytes.map { String(format: "%02x", $0) }.joined()
        
        // Format request body according to zkLogin docs
        let proofRequestBody: [String: Any] = [
            "maxEpoch": maxEpoch,
            "jwtRandomness": jwtRandomness,
            "keyClaimName": "sub",
            "ephemeralPublicKey": "0x" + publicKeyHex,
            "provider": "google",
            "jwt": token
        ]
        
        print("Using proof request URL: \(proofURL.absoluteString)")
        print("Using proof request body: \(proofRequestBody)")
        
        proofRequest.httpBody = try JSONSerialization.data(withJSONObject: proofRequestBody)
        print("Proof request body: \(String(data: proofRequest.httpBody!, encoding: .utf8) ?? "")")
        
        do {
            let (data, response) = try await session.data(for: proofRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid proof response type")
                throw NetworkError.invalidResponse
            }
            
            print("Proof response status code: \(httpResponse.statusCode)")
            print("Proof response headers: \(httpResponse.allHeaderFields)")
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("Proof response body: \(responseString)")
            }
            
            if httpResponse.statusCode != 200 {
                print("Full URL that failed: \(proofURL.absoluteString)")
                print("Request method: \(proofRequest.httpMethod ?? "unknown")")
                print("Request headers: \(proofRequest.allHTTPHeaderFields ?? [:])")
                throw NetworkError.serverError(statusCode: httpResponse.statusCode)
            }
            
            return data
        } catch {
            print("Network error: \(error.localizedDescription)")
            if let urlError = error as? URLError {
                print("URL Error code: \(urlError.code.rawValue)")
                print("URL Error description: \(urlError.localizedDescription)")
                print("Failed URL: \(urlError.failureURLString ?? "unknown")")
            }
            throw error
        }
    }
    
    deinit {
        monitor.cancel()
    }
}

struct NonceResponse: Codable {
    let nonce: String
    let epoch: Int
}

struct SaltResponse: Codable {
    let salt: String
}

struct SystemStateResponse: Codable {
    let epoch: Int
}

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int)
    case noConnection
    
    var errorDescription: String? {
        switch self {
            case .invalidURL:
                return "Invalid URL provided"
            case .invalidResponse:
                return "Invalid response received from server"
            case .serverError(let statusCode):
                return "Server error with status code: \(statusCode)"
            case .noConnection:
                return "No network connection available"
        }
    }
} 