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
    
    func getNonce(ephemeralPublicKey: String) async throws -> (nonce: String, randomness: String, epoch: Int, maxEpoch: Int) {
        guard let nonceURL = URL(string: "\(Constants.zkLoginEndpoint)/nonce") else {
            logger.error("Invalid nonce URL")
            throw NetworkError.invalidURL
        }
        
        var nonceRequest = URLRequest(url: nonceURL)
        nonceRequest.httpMethod = "POST"
        nonceRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        nonceRequest.setValue("Bearer \(Constants.enokiPublicKey)", forHTTPHeaderField: "Authorization")
        
        let nonceRequestBody: [String: Any] = [
            "network": Constants.network,
            "ephemeralPublicKey": ephemeralPublicKey,
            "additionalEpochs": Constants.maxEpochDuration
        ]
        
        nonceRequest.httpBody = try JSONSerialization.data(withJSONObject: nonceRequestBody)
        
        logger.info("""
        Sending nonce request:
        URL: \(nonceURL.absoluteString)
        Public Key: \(ephemeralPublicKey)
        Network: \(Constants.network)
        Additional Epochs: \(Constants.maxEpochDuration)
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
        
        logger.info("Successfully received nonce response")
        return (nonce, randomness, epoch, maxEpoch)
    }
    
    func sendZkLoginProofRequest(
        token: String,
        nonce: String,
        randomness: String,
        maxEpoch: Int,
        publicKey: String
    ) async throws -> Data {
        do {
            try await waitForConnection()
            
            // Log JWT token details
            logger.info("""
            -------- JWT Token Details --------
            Token Length: \(token.count)
            Expected Nonce: \(nonce)
            --------------------------------
            """)
            
            // Decode JWT parts for debugging
            let jwtParts = token.components(separatedBy: ".")
            if jwtParts.count == 3 {
                jwtParts.enumerated().forEach { index, part in
                    if let data = Data(base64Encoded: part.padding(toLength: ((part.count + 3) / 4) * 4, 
                                                                 withPad: "=", 
                                                                 startingAt: 0)),
                       let decodedString = String(data: data, encoding: .utf8) {
                        logger.info("JWT Part \(index): \(decodedString)")
                    }
                }
            }
            
            // Get salt using the nonce
            guard let saltURL = URL(string: Constants.zkLoginEndpoint) else {
                throw NetworkError.invalidURL
            }
            
            var saltRequest = URLRequest(url: saltURL)
            saltRequest.httpMethod = "GET"
            saltRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            saltRequest.setValue("Bearer \(Constants.enokiPublicKey)", forHTTPHeaderField: "Authorization")
            saltRequest.setValue(token, forHTTPHeaderField: "zklogin-jwt")
            saltRequest.setValue(nonce, forHTTPHeaderField: "zklogin-nonce")
            
            let (saltData, saltResponse) = try await session.data(for: saltRequest)
            
            guard let httpSaltResponse = saltResponse as? HTTPURLResponse else {
                logger.error("Invalid response type from salt endpoint")
                throw NetworkError.invalidResponse
            }
            
            if httpSaltResponse.statusCode != 200 {
                logger.error("Salt request failed with status code: \(httpSaltResponse.statusCode)")
                if let responseString = String(data: saltData, encoding: .utf8) {
                    logger.error("Error response: \(responseString)")
                }
                throw NetworkError.serverError(statusCode: httpSaltResponse.statusCode)
            }
            
            guard let saltResponseJson = try JSONSerialization.jsonObject(with: saltData) as? [String: Any],
                  let saltData = saltResponseJson["data"] as? [String: Any],
                  let userSalt = saltData["salt"] as? String else {
                throw NetworkError.invalidResponse
            }
            
            logger.info("Received salt: \(userSalt)")
            
            // Get proof using the nonce and salt
            guard let proofURL = URL(string: "\(Constants.zkLoginEndpoint)/zkp") else {
                logger.error("Invalid proof URL")
                throw NetworkError.invalidURL
            }
            
            var proofRequest = URLRequest(url: proofURL)
            proofRequest.httpMethod = "POST"
            proofRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            proofRequest.setValue("Bearer \(Constants.enokiPublicKey)", forHTTPHeaderField: "Authorization")
            proofRequest.setValue(token, forHTTPHeaderField: "zklogin-jwt")
            proofRequest.setValue(nonce, forHTTPHeaderField: "zklogin-nonce")
            proofRequest.timeoutInterval = Constants.proofTimeout
            
            let proofRequestBody: [String: Any] = [
                "network": Constants.network,
                "ephemeralPublicKey": publicKey,
                "maxEpoch": maxEpoch,
                "randomness": randomness,
                "nonce": nonce,
                "salt": userSalt
            ]
            
            proofRequest.httpBody = try JSONSerialization.data(withJSONObject: proofRequestBody)
            
            logger.info("""
            Sending proof request:
            Nonce: \(nonce)
            Public Key: \(publicKey)
            Max Epoch: \(maxEpoch)
            Salt: \(userSalt)
            JWT Token Length: \(token.count)
            """)
            
            let (proofData, proofResponse) = try await session.data(for: proofRequest)
            
            guard let proofHttpResponse = proofResponse as? HTTPURLResponse else {
                logger.error("Invalid response type from prover service")
                throw NetworkError.invalidResponse
            }
            
            if proofHttpResponse.statusCode != 200 {
                logger.error("Proof request failed with status code: \(proofHttpResponse.statusCode)")
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
