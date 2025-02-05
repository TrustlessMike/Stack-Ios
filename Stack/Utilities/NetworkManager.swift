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
    
    private func getNonce(ephemeralPublicKey: String) async throws -> (nonce: String, randomness: String, epoch: Int, maxEpoch: Int) {
        guard let nonceURL = URL(string: "\(Constants.proverBaseURL)/v1/zklogin/nonce") else {
            logger.error("Invalid nonce URL")
            throw NetworkError.invalidURL
        }
        
        var nonceRequest = URLRequest(url: nonceURL)
        nonceRequest.httpMethod = "POST"
        nonceRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        nonceRequest.setValue("Bearer \(Constants.enokiPublicKey)", forHTTPHeaderField: "Authorization")
        
        let nonceRequestBody: [String: Any] = [
            "network": "testnet",
            "ephemeralPublicKey": ephemeralPublicKey,
            "additionalEpochs": Constants.maxEpochDuration
        ]
        
        nonceRequest.httpBody = try JSONSerialization.data(withJSONObject: nonceRequestBody)
        
        logger.info("""
        -------- Nonce Request Details --------
        URL: \(nonceURL.absoluteString)
        Method: \(nonceRequest.httpMethod ?? "")
        Headers: \(nonceRequest.allHTTPHeaderFields ?? [:])
        Raw Request Body: \(String(data: nonceRequest.httpBody!, encoding: .utf8) ?? "")
        Ephemeral Public Key Length: \(ephemeralPublicKey.count)
        Ephemeral Public Key: \(ephemeralPublicKey)
        --------------------------------
        """)
        
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
            logger.error("Request headers: \(nonceRequest.allHTTPHeaderFields ?? [:])")
            throw NetworkError.serverError(statusCode: httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: nonceData) as? [String: Any],
              let data = json["data"] as? [String: Any],
              let nonce = data["nonce"] as? String,
              let randomness = data["randomness"] as? String,
              let epoch = data["epoch"] as? Int,
              let maxEpoch = data["maxEpoch"] as? Int else {
            logger.error("Invalid nonce response format")
            throw NetworkError.invalidResponse
        }
        
        logger.info("""
        Successfully received nonce response:
        Nonce: \(nonce)
        Randomness: \(randomness)
        Epoch: \(epoch)
        Max Epoch: \(maxEpoch)
        """)
        
        return (nonce, randomness, epoch, maxEpoch)
    }
    
    func sendZkLoginProofRequest(token: String) async throws -> Data {
        do {
            try await waitForConnection()
            
            logger.info("Starting ephemeral key generation...")
            currentEphemeralKey = EphemeralKey(validUntilEpoch: 0)
            guard let ephemeralKey = currentEphemeralKey else {
                logger.error("Failed to generate ephemeral key")
                throw NetworkError.keyGenerationFailed
            }
            
            let publicKeyBase64 = ephemeralKey.publicKeyBase64
            logger.info("""
            -------- Ephemeral Key Details --------
            Generated Public Key (Base64): \(publicKeyBase64)
            Public Key Length: \(publicKeyBase64.count)
            --------------------------------
            """)
            
            let (nonce, randomness, currentEpoch, maxEpoch) = try await getNonce(ephemeralPublicKey: publicKeyBase64)
            logger.info("Using Enoki-provided values - Nonce: \(nonce), Randomness: \(randomness)")
            
            currentEphemeralKey = EphemeralKey(validUntilEpoch: maxEpoch)
            
            guard let saltURL = URL(string: "\(Constants.proverBaseURL)/v1/zklogin") else {
                throw NetworkError.invalidURL
            }
            
            var saltRequest = URLRequest(url: saltURL)
            saltRequest.httpMethod = "GET"
            saltRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            saltRequest.setValue("Bearer \(Constants.enokiPublicKey)", forHTTPHeaderField: "Authorization")
            saltRequest.setValue(token, forHTTPHeaderField: "zklogin-jwt")
            
            let (saltData, _) = try await session.data(for: saltRequest)
            guard let saltResponse = try JSONSerialization.jsonObject(with: saltData) as? [String: Any],
                  let data = saltResponse["data"] as? [String: Any],
                  let userSalt = data["salt"] as? String else {
                throw NetworkError.invalidResponse
            }
            
            logger.info("Received user salt: \(userSalt)")
            
            guard let proofURL = URL(string: "\(Constants.proverBaseURL)/v1/zklogin/zkp") else {
                logger.error("Invalid proof URL")
                throw NetworkError.invalidURL
            }
            
            var proofRequest = URLRequest(url: proofURL)
            proofRequest.httpMethod = "POST"
            proofRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            proofRequest.setValue("Bearer \(Constants.enokiPublicKey)", forHTTPHeaderField: "Authorization")
            proofRequest.setValue(token, forHTTPHeaderField: "zklogin-jwt")
            proofRequest.timeoutInterval = Constants.proofTimeout
            
            let proofRequestBody: [String: Any] = [
                "network": "testnet",
                "ephemeralPublicKey": publicKeyBase64,
                "maxEpoch": maxEpoch,
                "randomness": randomness
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
    
    private func getCurrentEpoch() async throws -> (epoch: Int, rawJson: String) {
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
            guard let rawJsonString = String(data: systemStateData, encoding: .utf8) else {
                logger.error("Failed to convert response data to string")
                throw NetworkError.invalidResponse
            }
            
            logger.info("Raw RPC response: \(rawJsonString)")
            
            let json = try JSONSerialization.jsonObject(with: systemStateData) as? [String: Any]
            guard let result = json?["result"] as? [String: Any] else {
                logger.error("Missing result in RPC response")
                throw NetworkError.invalidResponse
            }
            
            var epoch: Int?
            
            if let directEpoch = result["epoch"] as? Int {
                epoch = directEpoch
            }
            else if let epochStr = result["epoch"] as? String, 
                    let epochInt = Int(epochStr) {
                epoch = epochInt
            }
            else if let systemState = result["systemState"] as? [String: Any],
                    let epochNum = systemState["epoch"] as? Int {
                epoch = epochNum
            }
            else if let data = result["data"] as? [String: Any],
                    let epochNum = data["epoch"] as? Int {
                epoch = epochNum
            }
            
            guard let validEpoch = epoch else {
                logger.error("Failed to find epoch in response. Available keys: \(result.keys.joined(separator: ", "))")
                throw NetworkError.invalidResponse
            }
            
            logger.info("Successfully parsed epoch: \(validEpoch)")
            return (epoch: validEpoch, rawJson: rawJsonString)
            
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