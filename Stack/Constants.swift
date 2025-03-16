import Foundation
import CryptoKit
import os

enum Constants {
    static let googleOAuthConfig = GoogleOAuthConfig(
        clientId: "211645280608-23hf7csv47gcbo6m5ntj2tlev0pj3qc6.apps.googleusercontent.com",
        redirectUri: "com.googleusercontent.apps.211645280608-23hf7csv47gcbo6m5ntj2tlev0pj3qc6:/oauth2callback",
        scope: "email profile openid"
    )
    
    // Using the Sui testnet endpoints
    static let apiBaseURL = "https://fullnode.testnet.sui.io"
    
    // UPDATED: zkLogin API Endpoints with multiple potential base URLs
    // Primary prover service (original)
    static let proverBaseURL = "https://api.enoki.mystenlabs.com"
    
    // Alternative prover services to try if primary fails
    static let altProverBaseURLs = [
        "https://api.zklogin.mystenlabs.com",           // Alternative 1
        "https://zklogin.api.mystenlabs.com",           // Alternative 2
        "https://enoki-api.zklogin.io",                 // Alternative 3
        "https://zkloginapi.mystenlabs.com"             // Alternative 4
    ]
    
    // Endpoint paths that can be combined with base URLs
    static let zkLoginPathV1 = "/v1/zklogin"
    static let zkLoginPathV2 = "/v2/zklogin"            // Try v2 if v1 fails
    static let zkLoginPathNoVersion = "/zklogin"        // Try without version if others fail
    
    // Default endpoints (will be adjusted dynamically if needed)
    static let zkLoginEndpoint = "\(proverBaseURL)\(zkLoginPathV1)"
    static let saltEndpoint = "\(zkLoginEndpoint)/salt"
    static let proofEndpoint = "\(zkLoginEndpoint)/proof"
    
    // Direct function to build a zkLogin URL with a specific base and path
    static func buildZkLoginURL(base: String, path: String, endpoint: String) -> String {
        return "\(base)\(path)/\(endpoint)"
    }
    
    // Flag to enable dynamic endpoint discovery
    static let enableEndpointFallbacks = true
    
    // Network configuration
    static let networkTimeout: TimeInterval = 30
    static let proofTimeout: TimeInterval = 60  // Increased timeout for proof generation
    
    // Enoki specific configurations
    static let enokiPublicKey = "enoki_public_340d1143bcdc3990013f2e8f83c7930a"
    static let maxEpochDuration = 2
    static let network = "testnet"
}

struct GoogleOAuthConfig {
    let clientId: String
    let redirectUri: String
    let scope: String
    
    var authURL: URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "prompt", value: "select_account"),
            URLQueryItem(name: "access_type", value: "offline")
        ]
        return components?.url
    }
}

// Add structures for JWT handling
struct JWTPayload: Codable {
    let iss: String?
    let sub: String?
    let aud: String?
    let exp: Int?
    let iat: Int?
}

// Add structure for ephemeral keys
struct EphemeralKey {
    let privateKey: Curve25519.Signing.PrivateKey
    let publicKey: Curve25519.Signing.PublicKey
    var validUntilEpoch: Int
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Stack", category: "EphemeralKey")
    
    enum KeyGenerationError: Error {
        case randomBytesGenerationFailed
        case invalidKeyLength
        case privateKeyCreationFailed
        case publicKeyValidationFailed
        case invalidBase64Encoding
        
        var localizedDescription: String {
            switch self {
            case .randomBytesGenerationFailed:
                return "Failed to generate secure random bytes"
            case .invalidKeyLength:
                return "Generated key has invalid length"
            case .privateKeyCreationFailed:
                return "Failed to create private key from bytes"
            case .publicKeyValidationFailed:
                return "Public key validation failed"
            case .invalidBase64Encoding:
                return "Failed to encode public key in base64"
            }
        }
    }
    
    init(validUntilEpoch: Int) throws {
        self.validUntilEpoch = validUntilEpoch
        
        logger.info("Starting Ed25519 key generation...")
        
        // Generate a new Ed25519 key pair
        let privateKey = Curve25519.Signing.PrivateKey()
        self.privateKey = privateKey
        self.publicKey = privateKey.publicKey
        
        // Validate public key
        let publicKeyBytes = publicKey.rawRepresentation
        guard publicKeyBytes.count == 32 else {
            logger.error("Invalid Ed25519 public key length: \(publicKeyBytes.count)")
            throw KeyGenerationError.invalidKeyLength
        }
        
        // Format the key as required by Sui zkLogin
        var formattedKey = Data([0x00]) // Add prefix byte 0x00 for Ed25519
        formattedKey.append(publicKeyBytes)
        
        // Validate the generated key can be properly encoded
        let base64String = formattedKey.base64EncodedString()
        guard Data(base64Encoded: base64String) != nil else {
            logger.error("Failed to validate base64 encoding of public key")
            throw KeyGenerationError.invalidBase64Encoding
        }
        
        logger.info("""
        Successfully generated Ed25519 key pair:
        Public key length: \(publicKeyBytes.count)
        Raw bytes (hex): \(publicKeyBytes.map { String(format: "%02x", $0) }.joined())
        Formatted key (hex): \(formattedKey.map { String(format: "%02x", $0) }.joined())
        Public key base64: \(base64String)
        """)
    }
    
    // Get the Ed25519 public key as standard base64 string
    var publicKeyBase64: String {
        let rawBytes = publicKey.rawRepresentation
        
        // Ed25519 public keys must be 32 bytes
        guard rawBytes.count == 32 else {
            logger.error("Invalid Ed25519 public key length: \(rawBytes.count)")
            fatalError("Invalid Ed25519 public key length")
        }
        
        // Format the key as required by Sui zkLogin
        var formattedKey = Data([0x00]) // Add prefix byte 0x00 for Ed25519
        formattedKey.append(rawBytes)
        
        // Use standard base64 encoding with padding
        let base64String = formattedKey.base64EncodedString()
        
        logger.debug("""
        Ed25519 public key encoding:
        Raw bytes length: \(rawBytes.count)
        Raw bytes (hex): \(rawBytes.map { String(format: "%02x", $0) }.joined())
        Formatted key (hex): \(formattedKey.map { String(format: "%02x", $0) }.joined())
        Base64 string: \(base64String)
        Base64 length: \(base64String.count)
        Is valid base64: \(Data(base64Encoded: base64String) != nil)
        """)
        
        return base64String
    }
    
    // Sign data with the Ed25519 private key
    func sign(_ data: Data) throws -> Data {
        do {
            let signature = try privateKey.signature(for: data)
            logger.info("Successfully signed data with Ed25519 private key")
            return signature
        } catch {
            logger.error("Failed to sign data: \(error.localizedDescription)")
            throw error
        }
    }
} 