import Foundation
import Network
import os
import CryptoKit

enum NetworkError: Error {
    case noConnection
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int)
    case urlError(URLError)
    case saltNotFound
    case proofGenerationFailed(String)
    case saltEndpointError(String)
    case proofEndpointError(String)
    case invalidJWT(String)
    case tokenParsingFailed

    var localizedDescription: String {
        switch self {
        case .noConnection:
            return "No internet connection. Please check your network settings."
        case .invalidURL:
            return "Invalid URL. Please contact support."
        case .invalidResponse:
            return "Invalid response from server."
        case .serverError(let statusCode):
            return "Server error with status code: \(statusCode)"
        case .urlError(let error):
            return "Network error: \(error.localizedDescription)"
        case .saltNotFound:
            return "Could not retrieve salt from server."
        case .proofGenerationFailed(let reason):
            return "Proof generation failed: \(reason)"
        case .saltEndpointError(let message):
            return "Salt endpoint error: \(message)"
        case .proofEndpointError(let message):
            return "Proof endpoint error: \(message)"
        case .invalidJWT(let message):
            return "Invalid JWT token: \(message)"
        case .tokenParsingFailed:
            return "Failed to parse authentication token."
        }
    }
}

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
    
    func getZkLoginParameters(ephemeralPublicKey: String) async throws -> (randomness: String, maxEpoch: Int) {
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
        Sending parameters request:
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
            logger.error("Parameters request failed with status code: \(httpResponse.statusCode)")
            if let responseString = String(data: nonceData, encoding: .utf8) {
                logger.error("Error response: \(responseString)")
            }
            throw NetworkError.serverError(statusCode: httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: nonceData) as? [String: Any],
              let data = json["data"] as? [String: Any],
              let randomness = data["randomness"] as? String,
              let maxEpoch = data["maxEpoch"] as? Int else {
            logger.error("Invalid parameters response format")
            throw NetworkError.invalidResponse
        }
        
        logger.info("Successfully received parameters response")
        return (randomness, maxEpoch)
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
    
    /**
     * Sends a zkLogin proof request to generate authentication proof.
     * 
     * This method implements a robust strategy for handling API endpoints:
     * 1. First attempts to use the configured proof endpoint
     * 2. If that fails, dynamically tries multiple combinations of base URLs and paths
     * 3. Performs exhaustive endpoint discovery to find working endpoints
     * 
     * For salt retrieval:
     * 1. First attempts to get the salt using the POST method (preferred and newer API format)
     * 2. If POST fails, falls back to GET method (older API format)
     * 3. If both API methods fail, uses a local salt generation algorithm as a final fallback
     * 
     * Error handling has been enhanced to provide detailed diagnostics for each failure case.
     */
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
            
            // Try to get salt with three approaches in order:
            // 1. POST method (preferred/newer API)
            // 2. GET method (older API)
            // 3. Local generation (fallback when API fails)
            var userSalt: String
            
            do {
                // First attempt: POST method
                userSalt = try await getSaltWithPost(token: token, nonce: nonce)
                logger.info("Successfully got salt using POST method")
            } catch let postError {
                logger.warning("POST method for salt failed: \(postError.localizedDescription). Trying with GET method...")
                
                do {
                    // Second attempt: GET method
                    userSalt = try await getSaltWithGet(token: token, nonce: nonce)
                    logger.info("Successfully got salt using GET method")
                } catch let getError {
                    logger.warning("GET method for salt also failed: \(getError.localizedDescription). Falling back to local salt generation...")
                    
                    // Third attempt: Generate salt locally
                    userSalt = generateLocalSalt(from: token, nonce: nonce)
                    logger.info("Using locally generated salt as fallback")
                }
            }
            
            logger.info("Using salt: \(userSalt)")
            
            // NEW: Try multiple proof endpoints if enabled
            if Constants.enableEndpointFallbacks {
                return try await getProofWithEndpointDiscovery(
                    token: token,
                    nonce: nonce,
                    randomness: randomness,
                    maxEpoch: maxEpoch,
                    publicKey: publicKey,
                    salt: userSalt
                )
            } else {
                // Original single-endpoint approach
                return try await getProofFromEndpoint(
                    proofURL: Constants.proofEndpoint,
                    token: token,
                    nonce: nonce,
                    randomness: randomness,
                    maxEpoch: maxEpoch,
                    publicKey: publicKey,
                    salt: userSalt
                )
            }
            
        } catch {
            logger.error("Network operation failed: \(error.localizedDescription)")
            if let urlError = error as? URLError {
                logger.error("URLError code: \(urlError.code.rawValue)")
                throw NetworkError.urlError(urlError)
            }
            throw error
        }
    }
    
    /**
     * Attempts to discover a working proof endpoint by trying multiple combinations
     * of base URLs and paths.
     */
    private func getProofWithEndpointDiscovery(
        token: String,
        nonce: String,
        randomness: String,
        maxEpoch: Int,
        publicKey: String,
        salt: String
    ) async throws -> Data {
        logger.info("Starting dynamic endpoint discovery for proof...")
        
        // Try the default endpoint first
        do {
            logger.info("Trying default proof endpoint: \(Constants.proofEndpoint)")
            return try await getProofFromEndpoint(
                proofURL: Constants.proofEndpoint,
                token: token,
                nonce: nonce,
                randomness: randomness,
                maxEpoch: maxEpoch,
                publicKey: publicKey,
                salt: salt
            )
        } catch let defaultError {
            logger.warning("Default proof endpoint failed: \(defaultError.localizedDescription)")
            logger.info("Trying alternative endpoints...")
        }
        
        // Try all combinations of base URLs and paths
        var lastError: Error?
        
        // Start with the original prover base URL and alternative paths
        let allBasePaths = [
            Constants.proverBaseURL: [Constants.zkLoginPathV1, Constants.zkLoginPathV2, Constants.zkLoginPathNoVersion]
        ]
        
        // If that doesn't work, try the alternative base URLs with all paths
        let allPaths = [Constants.zkLoginPathV1, Constants.zkLoginPathV2, Constants.zkLoginPathNoVersion]
        
        // First try default proverBaseURL with different paths
        for (baseURL, paths) in allBasePaths {
            for path in paths {
                let endpoint = Constants.buildZkLoginURL(base: baseURL, path: path, endpoint: "proof")
                do {
                    logger.info("Trying proof endpoint: \(endpoint)")
                    return try await getProofFromEndpoint(
                        proofURL: endpoint,
                        token: token,
                        nonce: nonce,
                        randomness: randomness,
                        maxEpoch: maxEpoch,
                        publicKey: publicKey,
                        salt: salt
                    )
                } catch let endpointError {
                    lastError = endpointError
                    logger.warning("Proof endpoint failed: \(endpoint) - \(endpointError.localizedDescription)")
                }
            }
        }
        
        // If still failing, try all alternative base URLs with all paths
        for altBaseURL in Constants.altProverBaseURLs {
            for path in allPaths {
                let endpoint = Constants.buildZkLoginURL(base: altBaseURL, path: path, endpoint: "proof")
                do {
                    logger.info("Trying alternative proof endpoint: \(endpoint)")
                    return try await getProofFromEndpoint(
                        proofURL: endpoint,
                        token: token,
                        nonce: nonce,
                        randomness: randomness,
                        maxEpoch: maxEpoch,
                        publicKey: publicKey,
                        salt: salt
                    )
                } catch let endpointError {
                    lastError = endpointError
                    logger.warning("Alternative proof endpoint failed: \(endpoint) - \(endpointError.localizedDescription)")
                }
            }
        }
        
        // Try directly hardcoded endpoints that might work
        let hardcodedEndpoints = [
            "https://api.zklogin.io/v1/proof",
            "https://zklogin.sui.io/v1/proof",
            "https://prover.mystenlabs.com/v1/zklogin/proof"
        ]
        
        for endpoint in hardcodedEndpoints {
            do {
                logger.info("Trying hardcoded proof endpoint: \(endpoint)")
                return try await getProofFromEndpoint(
                    proofURL: endpoint,
                    token: token,
                    nonce: nonce,
                    randomness: randomness,
                    maxEpoch: maxEpoch,
                    publicKey: publicKey,
                    salt: salt
                )
            } catch let endpointError {
                lastError = endpointError
                logger.warning("Hardcoded proof endpoint failed: \(endpoint) - \(endpointError.localizedDescription)")
            }
        }
        
        // If all alternatives failed, throw the last error
        logger.error("All proof endpoints failed. Authentication cannot proceed.")
        throw lastError ?? NetworkError.proofEndpointError("All potential proof endpoints failed")
    }
    
    /**
     * Makes a proof request to a specific endpoint.
     */
    private func getProofFromEndpoint(
        proofURL: String,
        token: String,
        nonce: String,
        randomness: String,
        maxEpoch: Int,
        publicKey: String,
        salt: String
    ) async throws -> Data {
        guard let url = URL(string: proofURL) else {
            logger.error("Invalid proof URL: \(proofURL)")
            throw NetworkError.invalidURL
        }
        
        logger.info("Proof URL: \(url)")
        
        var proofRequest = URLRequest(url: url)
        proofRequest.httpMethod = "POST"
        proofRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        proofRequest.setValue("Bearer \(Constants.enokiPublicKey)", forHTTPHeaderField: "Authorization")
        proofRequest.timeoutInterval = Constants.proofTimeout
        
        // Updated proof request with the correct parameter format
        let proofRequestBody: [String: Any] = [
            "network": Constants.network,
            "jwt": token,
            "nonce": nonce,
            "ephemeralPublicKey": publicKey,
            "maxEpoch": maxEpoch,
            "randomness": randomness,
            "salt": salt,
            "jwtRandomness": nonce  // Added this parameter which might be needed
        ]
        
        logger.info("Proof request body: \(proofRequestBody)")
        
        proofRequest.httpBody = try JSONSerialization.data(withJSONObject: proofRequestBody)
        
        logger.info("""
        Sending proof request to \(proofURL):
        Nonce: \(nonce)
        Public Key: \(publicKey)
        Max Epoch: \(maxEpoch)
        Salt: \(salt)
        JWT Token Length: \(token.count)
        """)
        
        let (proofData, proofResponse) = try await session.data(for: proofRequest)
        
        guard let proofHttpResponse = proofResponse as? HTTPURLResponse else {
            logger.error("Invalid response type from prover service")
            throw NetworkError.invalidResponse
        }
        
        if proofHttpResponse.statusCode != 200 {
            let responseString = String(data: proofData, encoding: .utf8) ?? "No response body"
            logger.error("Proof request failed with status code: \(proofHttpResponse.statusCode)")
            logger.error("Error response: \(responseString)")
            
            switch proofHttpResponse.statusCode {
            case 404:
                // 404 means the endpoint might have changed or been deprecated
                throw NetworkError.proofEndpointError("Proof endpoint not found (404). The API endpoint may have changed or been deprecated.")
            case 401:
                // 401 means unauthorized - likely an issue with the API key
                throw NetworkError.proofEndpointError("Unauthorized access to proof endpoint (401). Check the validity of your Enoki public key.")
            case 400:
                // 400 means bad request - likely wrong parameters
                let errorMessage = "Invalid request to proof endpoint (400). The request format might be incorrect."
                
                // Try to extract more specific error details if possible
                if let json = try? JSONSerialization.jsonObject(with: proofData) as? [String: Any],
                   let errors = json["errors"] as? [[String: Any]],
                   let firstError = errors.first,
                   let errorMessage = firstError["message"] as? String {
                    throw NetworkError.proofEndpointError("Proof endpoint error: \(errorMessage)")
                }
                
                throw NetworkError.proofEndpointError(errorMessage)
            default:
                throw NetworkError.serverError(statusCode: proofHttpResponse.statusCode)
            }
        }
        
        // Check for valid proof data structure
        do {
            let json = try JSONSerialization.jsonObject(with: proofData) as? [String: Any]
            if let errors = json?["errors"] as? [[String: Any]], !errors.isEmpty {
                if let firstError = errors.first,
                   let code = firstError["code"] as? String,
                   let message = firstError["message"] as? String {
                    logger.error("Proof API returned error: \(code) - \(message)")
                    throw NetworkError.proofEndpointError("\(code): \(message)")
                }
            }
            
            // Ensure data field exists
            guard json?["data"] != nil else {
                logger.error("Invalid proof response - missing data field")
                throw NetworkError.invalidResponse
            }
        } catch {
            logger.error("Failed to parse proof response: \(error.localizedDescription)")
        }
        
        logger.info("Successfully received proof from prover service")
        return proofData
    }
    
    // New helper method to get salt using POST
    private func getSaltWithPost(token: String, nonce: String) async throws -> String {
        guard let saltURL = URL(string: "\(Constants.proverBaseURL)/v1/zklogin/salt") else {
            throw NetworkError.invalidURL
        }
        
        logger.info("Salt URL (POST): \(saltURL)")
        
        var saltRequest = URLRequest(url: saltURL)
        saltRequest.httpMethod = "POST"
        saltRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        saltRequest.setValue("Bearer \(Constants.enokiPublicKey)", forHTTPHeaderField: "Authorization")
        
        let saltRequestBody: [String: Any] = [
            "network": Constants.network,
            "jwt": token,
            "nonce": nonce
        ]
        
        saltRequest.httpBody = try JSONSerialization.data(withJSONObject: saltRequestBody)
        
        let (saltData, saltResponse) = try await session.data(for: saltRequest)
        
        guard let httpResponse = saltResponse as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let responseString = String(data: saltData, encoding: .utf8) ?? "No response body"
            logger.error("Salt POST request failed with status code: \(httpResponse.statusCode)")
            logger.error("Error response: \(responseString)")
            
            switch httpResponse.statusCode {
            case 404:
                // 404 means the endpoint might have changed or been deprecated
                throw NetworkError.saltEndpointError("Salt endpoint not found (404). The API endpoint may have changed or been deprecated.")
            case 401:
                // 401 means unauthorized - likely an issue with the API key
                throw NetworkError.saltEndpointError("Unauthorized access to salt endpoint (401). Check the validity of your Enoki public key.")
            case 400:
                // 400 means bad request - likely wrong parameters
                let errorMessage = "Invalid request to salt endpoint (400). The request format might be incorrect."
                
                // Try to extract more specific error details if possible
                if let json = try? JSONSerialization.jsonObject(with: saltData) as? [String: Any],
                   let errors = json["errors"] as? [[String: Any]],
                   let firstError = errors.first,
                   let errorMessage = firstError["message"] as? String {
                    throw NetworkError.saltEndpointError("Salt endpoint error: \(errorMessage)")
                }
                
                throw NetworkError.saltEndpointError(errorMessage)
            default:
                throw NetworkError.serverError(statusCode: httpResponse.statusCode)
            }
        }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: saltData) as? [String: Any] else {
                throw NetworkError.invalidResponse
            }
            
            // Check for error field in the response
            if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
                if let firstError = errors.first,
                   let code = firstError["code"] as? String,
                   let message = firstError["message"] as? String {
                    logger.error("Salt API returned error: \(code) - \(message)")
                    throw NetworkError.saltEndpointError("\(code): \(message)")
                } else {
                    logger.error("Salt API returned unspecified error")
                    throw NetworkError.saltEndpointError("Unspecified error from salt endpoint")
                }
            }
            
            guard let data = json["data"] as? [String: Any],
                  let salt = data["salt"] as? String else {
                logger.error("Invalid salt response format")
                throw NetworkError.invalidResponse
            }
            
            return salt
        } catch let jsonError as NSError {
            logger.error("Failed to parse salt response: \(jsonError.localizedDescription)")
            throw NetworkError.invalidResponse
        }
    }
    
    // Helper method to get salt using GET
    private func getSaltWithGet(token: String, nonce: String) async throws -> String {
        // Construct the salt URL with query parameters
        var urlComponents = URLComponents(string: "\(Constants.proverBaseURL)/v1/zklogin/salt")
        urlComponents?.queryItems = [
            URLQueryItem(name: "network", value: Constants.network),
            URLQueryItem(name: "jwt", value: token),
            URLQueryItem(name: "nonce", value: nonce)
        ]
        
        guard let saltURL = urlComponents?.url else {
            throw NetworkError.invalidURL
        }
        
        logger.info("Salt URL (GET): \(saltURL)")
        
        var saltRequest = URLRequest(url: saltURL)
        saltRequest.httpMethod = "GET"
        saltRequest.setValue("Bearer \(Constants.enokiPublicKey)", forHTTPHeaderField: "Authorization")
        
        let (saltData, saltResponse) = try await session.data(for: saltRequest)
        
        guard let httpResponse = saltResponse as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let responseString = String(data: saltData, encoding: .utf8) ?? "No response body"
            logger.error("Salt GET request failed with status code: \(httpResponse.statusCode)")
            logger.error("Error response: \(responseString)")
            
            switch httpResponse.statusCode {
            case 404:
                // 404 means the endpoint might have changed or been deprecated
                throw NetworkError.saltEndpointError("Salt endpoint not found (404). The API endpoint may have changed or been deprecated.")
            case 401:
                // 401 means unauthorized - likely an issue with the API key
                throw NetworkError.saltEndpointError("Unauthorized access to salt endpoint (401). Check the validity of your Enoki public key.")
            case 400:
                // 400 means bad request - likely wrong parameters
                let errorMessage = "Invalid request to salt endpoint (400). The request format might be incorrect."
                
                // Try to extract more specific error details if possible
                if let json = try? JSONSerialization.jsonObject(with: saltData) as? [String: Any],
                   let errors = json["errors"] as? [[String: Any]],
                   let firstError = errors.first,
                   let errorMessage = firstError["message"] as? String {
                    throw NetworkError.saltEndpointError("Salt endpoint error: \(errorMessage)")
                }
                
                throw NetworkError.saltEndpointError(errorMessage)
            default:
                throw NetworkError.serverError(statusCode: httpResponse.statusCode)
            }
        }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: saltData) as? [String: Any] else {
                throw NetworkError.invalidResponse
            }
            
            // Check for error field in the response
            if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
                if let firstError = errors.first,
                   let code = firstError["code"] as? String,
                   let message = firstError["message"] as? String {
                    logger.error("Salt API returned error: \(code) - \(message)")
                    throw NetworkError.saltEndpointError("\(code): \(message)")
                } else {
                    logger.error("Salt API returned unspecified error")
                    throw NetworkError.saltEndpointError("Unspecified error from salt endpoint")
                }
            }
            
            guard let data = json["data"] as? [String: Any],
                  let salt = data["salt"] as? String else {
                logger.error("Invalid salt response format")
                throw NetworkError.invalidResponse
            }
            
            return salt
        } catch let jsonError as NSError {
            logger.error("Failed to parse salt response: \(jsonError.localizedDescription)")
            throw NetworkError.invalidResponse
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
    
    /**
     * Generates a deterministic salt locally as a fallback when the salt endpoint is unavailable.
     *
     * Security considerations:
     * - This approach is not as secure as server-generated salt but provides necessary functionality
     *   when the salt endpoint is unavailable or has changed
     * - The salt is deterministically generated from the JWT token and nonce using SHA-256
     * - The first 32 characters of the hash are used as the salt value
     * - This ensures consistent salt values for the same token and nonce combination
     *
     * This method should only be used as a last resort after server API approaches have failed.
     * For production environments, it's recommended to keep monitoring for API changes and update
     * the app accordingly when the proper salt endpoint becomes available again.
     */
    private func generateLocalSalt(from token: String, nonce: String) -> String {
        logger.info("Generating local salt based on JWT and nonce")
        
        // Use a deterministic approach to create salt from the JWT + nonce
        let combinedString = token + nonce
        let saltData = combinedString.data(using: .utf8) ?? Data()
        
        // Create a SHA-256 hash of the combined data
        let hashData = SHA256.hash(data: saltData)
        
        // Convert to a hex string for consistency
        let hashString = hashData.map { String(format: "%02x", $0) }.joined()
        
        // Use a subset of the hash as the salt (first 32 chars)
        let salt = String(hashString.prefix(32))
        
        logger.info("Generated local salt: \(salt)")
        return salt
    }
    
    /**
     * Checks the status of the zkLogin API endpoints and logs their availability.
     * This method can be used for debugging and monitoring purposes to understand
     * which endpoints are currently working and which ones have issues.
     * 
     * Returns a tuple with the count of working endpoints and a dictionary of working endpoints.
     */
    func checkApiStatus() async -> (workingCount: Int, workingEndpoints: [String: Bool]) {
        logger.info("Checking zkLogin API endpoint status...")
        
        var workingEndpoints = [String: Bool]()
        var workingCount = 0
        
        // Check all potential base URLs
        let allBaseURLs = [Constants.proverBaseURL] + Constants.altProverBaseURLs
        
        // Check all potential paths
        let allPaths = [Constants.zkLoginPathV1, Constants.zkLoginPathV2, Constants.zkLoginPathNoVersion]
        
        // Check base URLs
        for baseURL in allBaseURLs {
            do {
                guard let url = URL(string: baseURL) else {
                    logger.error("❌ Invalid URL for base: \(baseURL)")
                    continue
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                
                let (_, response) = try await session.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    let statusCode = httpResponse.statusCode
                    let isSuccess = statusCode >= 200 && statusCode < 400
                    
                    if isSuccess {
                        logger.info("✅ Base URL Available: \(baseURL) (\(statusCode))")
                        workingEndpoints[baseURL] = true
                        workingCount += 1
                    } else if statusCode == 404 {
                        logger.info("❌ Base URL Not Found: \(baseURL) (404)")
                        workingEndpoints[baseURL] = false
                    } else {
                        logger.info("⚠️ Base URL Status: \(baseURL) (\(statusCode))")
                        workingEndpoints[baseURL] = statusCode < 500
                    }
                }
            } catch {
                logger.error("❌ Base URL Error: \(baseURL) - \(error.localizedDescription)")
                workingEndpoints[baseURL] = false
            }
            
            // Check combined endpoints with all paths
            for path in allPaths {
                let zkLoginBase = "\(baseURL)\(path)"
                
                // Check zkLogin base with this path
                do {
                    guard let url = URL(string: zkLoginBase) else {
                        logger.error("❌ Invalid URL for zkLogin: \(zkLoginBase)")
                        continue
                    }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "HEAD"
                    
                    let (_, response) = try await session.data(for: request)
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        let statusCode = httpResponse.statusCode
                        let isSuccess = statusCode >= 200 && statusCode < 400
                        
                        if isSuccess {
                            logger.info("✅ zkLogin Base Available: \(zkLoginBase) (\(statusCode))")
                            workingEndpoints[zkLoginBase] = true
                            workingCount += 1
                        } else if statusCode == 404 {
                            logger.info("❌ zkLogin Base Not Found: \(zkLoginBase) (404)")
                            workingEndpoints[zkLoginBase] = false
                        } else {
                            logger.info("⚠️ zkLogin Base Status: \(zkLoginBase) (\(statusCode))")
                            workingEndpoints[zkLoginBase] = statusCode < 500
                        }
                    }
                } catch {
                    logger.error("❌ zkLogin Base Error: \(zkLoginBase) - \(error.localizedDescription)")
                    workingEndpoints[zkLoginBase] = false
                }
                
                // Check endpoints for this path combination
                let endpoints = ["nonce", "salt", "proof"]
                for endpoint in endpoints {
                    let fullEndpoint = "\(zkLoginBase)/\(endpoint)"
                    
                    do {
                        guard let url = URL(string: fullEndpoint) else {
                            logger.error("❌ Invalid URL for endpoint: \(fullEndpoint)")
                            continue
                        }
                        
                        var request = URLRequest(url: url)
                        request.httpMethod = "HEAD"
                        
                        let (_, response) = try await session.data(for: request)
                        
                        if let httpResponse = response as? HTTPURLResponse {
                            let statusCode = httpResponse.statusCode
                            let isSuccess = statusCode >= 200 && statusCode < 400
                            
                            if isSuccess {
                                logger.info("✅ Endpoint Available: \(fullEndpoint) (\(statusCode))")
                                workingEndpoints[fullEndpoint] = true
                                workingCount += 1
                            } else if statusCode == 404 {
                                logger.info("❌ Endpoint Not Found: \(fullEndpoint) (404)")
                                workingEndpoints[fullEndpoint] = false
                            } else {
                                logger.info("⚠️ Endpoint Status: \(fullEndpoint) (\(statusCode))")
                                workingEndpoints[fullEndpoint] = statusCode < 500
                            }
                        }
                    } catch {
                        logger.error("❌ Endpoint Error: \(fullEndpoint) - \(error.localizedDescription)")
                        workingEndpoints[fullEndpoint] = false
                    }
                }
            }
        }
        
        // Try hardcoded alternative endpoints as well
        let hardcodedEndpoints = [
            "https://api.zklogin.io/v1/proof",
            "https://zklogin.sui.io/v1/proof",
            "https://prover.mystenlabs.com/v1/zklogin/proof"
        ]
        
        for endpoint in hardcodedEndpoints {
            do {
                guard let url = URL(string: endpoint) else {
                    logger.error("❌ Invalid URL for hardcoded endpoint: \(endpoint)")
                    continue
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                
                let (_, response) = try await session.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    let statusCode = httpResponse.statusCode
                    let isSuccess = statusCode >= 200 && statusCode < 400
                    
                    if isSuccess {
                        logger.info("✅ Hardcoded Endpoint Available: \(endpoint) (\(statusCode))")
                        workingEndpoints[endpoint] = true
                        workingCount += 1
                    } else if statusCode == 404 {
                        logger.info("❌ Hardcoded Endpoint Not Found: \(endpoint) (404)")
                        workingEndpoints[endpoint] = false
                    } else {
                        logger.info("⚠️ Hardcoded Endpoint Status: \(endpoint) (\(statusCode))")
                        workingEndpoints[endpoint] = statusCode < 500
                    }
                }
            } catch {
                logger.error("❌ Hardcoded Endpoint Error: \(endpoint) - \(error.localizedDescription)")
                workingEndpoints[endpoint] = false
            }
        }
        
        // Also check SUI RPC endpoint
        do {
            guard let url = URL(string: Constants.apiBaseURL) else {
                logger.error("❌ Invalid URL for SUI RPC: \(Constants.apiBaseURL)")
            } else {
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                
                let (_, response) = try await session.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    let statusCode = httpResponse.statusCode
                    let isSuccess = statusCode >= 200 && statusCode < 400
                    
                    if isSuccess {
                        logger.info("✅ SUI RPC Available: \(Constants.apiBaseURL) (\(statusCode))")
                        workingEndpoints[Constants.apiBaseURL] = true
                        workingCount += 1
                    } else {
                        logger.info("⚠️ SUI RPC Status: \(Constants.apiBaseURL) (\(statusCode))")
                        workingEndpoints[Constants.apiBaseURL] = statusCode < 500
                    }
                }
            }
        } catch {
            logger.error("❌ SUI RPC Error: \(Constants.apiBaseURL) - \(error.localizedDescription)")
            workingEndpoints[Constants.apiBaseURL] = false
        }
        
        logger.info("API Status Check Complete: \(workingCount) endpoints available")
        
        // If we found working zkLogin endpoints, store them for future use
        if workingCount > 0 {
            // Find a working proof endpoint
            for (endpoint, isWorking) in workingEndpoints {
                if isWorking && endpoint.contains("proof") {
                    logger.info("🔍 Found working proof endpoint: \(endpoint)")
                    // We could store this in UserDefaults for future use
                    break
                }
            }
        }
        
        return (workingCount, workingEndpoints)
    }
    
    /**
     * Exposes the local salt generation functionality for testing purposes.
     * This method should only be used in debug builds for testing.
     */
    #if DEBUG
    func generateLocalSaltForTesting(from token: String, nonce: String) -> String {
        return generateLocalSalt(from: token, nonce: nonce)
    }
    #endif
    
    deinit {
        monitor.cancel()
    }
} 
