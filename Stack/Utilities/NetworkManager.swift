import Foundation
import Network
import os
import CryptoKit

class NetworkManager {
    static let shared = NetworkManager()
    private let session: URLSession
    private let monitor = NWPathMonitor()
    private var isConnected = false
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var currentEphemeralKey: EphemeralKey?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Stack", category: "NetworkManager")
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.networkTimeout
        config.timeoutIntervalForResource = Constants.networkTimeout
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
            self?.logger.info("Network status changed: \(path.status == .satisfied ? "Connected" : "Disconnected")")
            
            if path.status == .satisfied {
                self?.connectionContinuation?.resume(returning: ())
            } else {
                self?.connectionContinuation?.resume(throwing: NetworkError.noConnection)
            }
            self?.connectionContinuation = nil
        }
        monitor.start(queue: DispatchQueue.global())
    }
    
    private func waitForConnection() async throws {
        if isConnected { return }
        logger.info("Waiting for network connection...")
        return try await withCheckedThrowingContinuation { continuation in
            self.connectionContinuation = continuation
        }
    }
    
    private func getNonce(address: String) async throws -> String {
        guard let nonceURL = URL(string: "\(Constants.proverBaseURL)/nonce") else {
            logger.error("Invalid nonce URL")
            throw NetworkError.invalidURL
        }
        
        var nonceRequest = URLRequest(url: nonceURL)
        nonceRequest.httpMethod = "POST"
        nonceRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let nonceRequestBody: [String: Any] = [
            "address": address
        ]
        
        nonceRequest.httpBody = try JSONSerialization.data(withJSONObject: nonceRequestBody)
        
        logger.info("Requesting nonce for address: \(address)")
        let (nonceData, nonceResponse) = try await session.data(for: nonceRequest)
        
        guard let httpResponse = nonceResponse as? HTTPURLResponse else {
            logger.error("Invalid response type from nonce endpoint")
            throw NetworkError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            logger.error("Nonce request failed with status code: \(httpResponse.statusCode)")
            if let responseString = String(data: nonceData, encoding: .utf8) {
                logger.error("Error response: \(responseString)")
            }
            throw NetworkError.serverError(statusCode: httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: nonceData) as? [String: Any],
              let nonce = json["nonce"] as? String else {
            logger.error("Invalid nonce response format")
            throw NetworkError.invalidResponse
        }
        
        logger.info("Successfully received nonce: \(nonce)")
        return nonce
    }
    
    private func generateNonce(publicKey: String, maxEpoch: Int, randomness: String) -> String {
        // Combine inputs in the same order as @mysten/zklogin SDK
        let input = "\(publicKey)\(maxEpoch)\(randomness)"
        
        // Hash the combined input using SHA-256 (same as SDK)
        let inputData = input.data(using: .utf8)!
        let hashedData = SHA256.hash(data: inputData)
        
        // Convert hash to hex string without 0x prefix
        let nonce = hashedData.map { String(format: "%02x", $0) }.joined()
        
        logger.info("""
        Generated nonce with components:
        Public Key: \(publicKey)
        Max Epoch: \(maxEpoch)
        Randomness: \(randomness)
        Generated Nonce: \(nonce)
        """)
        
        return nonce
    }
    
    private func generateRandomness() -> String {
        var randomBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        return randomBytes.map { String(format: "%02x", $0) }.joined()
    }
    
    func sendZkLoginProofRequest(token: String) async throws -> Data {
        do {
            try await waitForConnection()
            
            // Step 1: Get current epoch and calculate maxEpoch
            logger.info("Fetching current epoch...")
            let currentEpoch = try await getCurrentEpoch()
            let maxEpoch = currentEpoch + Constants.maxEpochDuration // e.g., +10 epochs
            logger.info("Current epoch: \(currentEpoch), maxEpoch: \(maxEpoch)")
            
            // Step 2: Generate ephemeral key pair
            currentEphemeralKey = EphemeralKey(validUntilEpoch: maxEpoch)
            guard let ephemeralKey = currentEphemeralKey else {
                logger.error("Failed to generate ephemeral key")
                throw NetworkError.keyGenerationFailed
            }
            
            // Step 3: Generate randomness (same as SDK's generateRandomness())
            let randomness = generateRandomness()
            logger.info("Generated randomness: \(randomness)")
            
            // Step 4: Generate nonce using the same format as SDK
            let publicKeyBase64 = ephemeralKey.publicKeyBase64
            let nonce = generateNonce(
                publicKey: publicKeyBase64,
                maxEpoch: maxEpoch,
                randomness: randomness
            )
            logger.info("Generated nonce: \(nonce)")
            
            // Step 5: Get salt from salt service
            guard let saltURL = URL(string: "\(Constants.proverBaseURL)/salt") else {
                throw NetworkError.invalidURL
            }
            
            var saltRequest = URLRequest(url: saltURL)
            saltRequest.httpMethod = "POST"
            saltRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let saltRequestBody: [String: Any] = ["token": token]
            saltRequest.httpBody = try JSONSerialization.data(withJSONObject: saltRequestBody)
            
            let (saltData, _) = try await session.data(for: saltRequest)
            guard let saltResponse = try JSONSerialization.jsonObject(with: saltData) as? [String: Any],
                  let userSalt = saltResponse["salt"] as? String else {
                throw NetworkError.invalidResponse
            }
            
            logger.info("Received user salt: \(userSalt)")
            
            // Step 6: Get proof from prover service
            guard let proofURL = URL(string: "\(Constants.proverBaseURL)/v1/zklogin/prove") else {
                logger.error("Invalid proof URL: \(Constants.zkLoginAPIEndpoint)")
                throw NetworkError.invalidURL
            }
            
            var proofRequest = URLRequest(url: proofURL)
            proofRequest.httpMethod = "POST"
            proofRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            proofRequest.setValue(Constants.enokiPublicKey, forHTTPHeaderField: "X-API-Key")
            proofRequest.timeoutInterval = Constants.proofTimeout
            
            let proofRequestBody: [String: Any] = [
                "network": "testnet",
                "epoch": currentEpoch,
                "maxEpoch": maxEpoch,
                "keyPair": [
                    "publicKey": publicKeyBase64
                ],
                "jwt": token,
                "jwtRandomness": randomness,
                "userSalt": userSalt,
                "nonce": nonce
            ]
            
            proofRequest.httpBody = try JSONSerialization.data(withJSONObject: proofRequestBody)
            
            logger.info("Sending proof request to: \(proofURL.absoluteString)")
            logger.info("Using X-API-Key: \(Constants.enokiPublicKey)")
            if let requestBody = String(data: proofRequest.httpBody!, encoding: .utf8) {
                logger.info("Proof request body: \(requestBody)")
            }
            logger.info("Request headers: \(proofRequest.allHTTPHeaderFields ?? [:])")
            
            let (proofData, proofResponse) = try await session.data(for: proofRequest)
            
            guard let proofHttpResponse = proofResponse as? HTTPURLResponse else {
                logger.error("Invalid response type from prover service")
                throw NetworkError.invalidResponse
            }
            
            if proofHttpResponse.statusCode != 200 {
                logger.error("Proof request failed with status code: \(proofHttpResponse.statusCode)")
                logger.error("Response headers: \(proofHttpResponse.allHeaderFields)")
                if let responseString = String(data: proofData, encoding: .utf8) {
                    logger.error("Error response: \(responseString)")
                }
                throw NetworkError.serverError(statusCode: proofHttpResponse.statusCode)
            }
            
            logger.info("Successfully received proof from prover service")
            return proofData
            
        } catch {
            logger.error("Network operation failed: \(error.localizedDescription)")
            if let urlError = error as? URLError {
                logger.error("URLError code: \(urlError.code.rawValue)")
                throw NetworkError.urlError(urlError)
            }
            throw error
        }
    }
    
    private func getCurrentEpoch() async throws -> Int {
        guard let systemStateURL = URL(string: Constants.apiBaseURL) else {
            logger.error("Invalid RPC URL: \(Constants.apiBaseURL)")
            throw NetworkError.invalidURL
        }
        
        var systemStateRequest = URLRequest(url: systemStateURL)
        systemStateRequest.httpMethod = "POST"
        systemStateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        systemStateRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let rpcRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "suix_getLatestSuiSystemState",
            "params": []
        ]
        
        systemStateRequest.httpBody = try JSONSerialization.data(withJSONObject: rpcRequest)
        
        logger.info("Sending RPC request to: \(systemStateURL.absoluteString)")
        if let requestBody = String(data: systemStateRequest.httpBody!, encoding: .utf8) {
            logger.info("Request body: \(requestBody)")
        }
        
        let (systemStateData, systemStateResponse) = try await session.data(for: systemStateRequest)
        
        guard let httpResponse = systemStateResponse as? HTTPURLResponse else {
            logger.error("Invalid response type from RPC endpoint")
            throw NetworkError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            logger.error("RPC request failed with status code: \(httpResponse.statusCode)")
            if let responseString = String(data: systemStateData, encoding: .utf8) {
                logger.error("Error response: \(responseString)")
            }
            throw NetworkError.serverError(statusCode: httpResponse.statusCode)
        }
        
        do {
            // Log the raw response for debugging
            if let responseString = String(data: systemStateData, encoding: .utf8) {
                logger.info("Raw RPC response: \(responseString)")
            }
            
            let json = try JSONSerialization.jsonObject(with: systemStateData) as? [String: Any]
            guard let result = json?["result"] as? [String: Any] else {
                logger.error("Missing result in RPC response")
                throw NetworkError.invalidResponse
            }
            
            // Try different paths to find epoch
            var epoch: Int?
            
            // Try direct epoch field
            if let directEpoch = result["epoch"] as? Int {
                epoch = directEpoch
            }
            // Try epoch as string
            else if let epochStr = result["epoch"] as? String, 
                    let epochInt = Int(epochStr) {
                epoch = epochInt
            }
            // Try system state path
            else if let systemState = result["systemState"] as? [String: Any],
                    let epochNum = systemState["epoch"] as? Int {
                epoch = epochNum
            }
            // Try data path
            else if let data = result["data"] as? [String: Any],
                    let epochNum = data["epoch"] as? Int {
                epoch = epochNum
            }
            
            guard let validEpoch = epoch else {
                logger.error("Failed to find epoch in response. Available keys: \(result.keys.joined(separator: ", "))")
                throw NetworkError.invalidResponse
            }
            
            logger.info("Successfully parsed epoch: \(validEpoch)")
            return validEpoch
            
        } catch {
            logger.error("Failed to parse RPC response: \(error.localizedDescription)")
            throw NetworkError.invalidResponse
        }
    }
    
    deinit {
        monitor.cancel()
    }
}

enum NetworkError: Error {
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int)
    case noConnection
    case keyGenerationFailed
    case urlError(URLError)
    
    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid URL configuration"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error: \(code)"
        case .noConnection:
            return "No network connection"
        case .keyGenerationFailed:
            return "Failed to generate ephemeral key"
        case .urlError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
} 