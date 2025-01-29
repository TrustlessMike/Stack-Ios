import Foundation
import CryptoKit

enum Constants {
    static let googleOAuthConfig = GoogleOAuthConfig(
        clientId: "211645280608-23hf7csv47gcbo6m5ntj2tlev0pj3qc6.apps.googleusercontent.com",
        redirectUri: "com.googleusercontent.apps.211645280608-23hf7csv47gcbo6m5ntj2tlev0pj3qc6:/oauth2callback",
        scope: "email profile openid"
    )
    
    // Using the Sui testnet endpoints
    static let apiBaseURL = "https://fullnode.testnet.sui.io"
    static let rpcEndpoint = apiBaseURL  // Base URL for RPC calls
    
    // Enoki service endpoints
    static let proverBaseURL = "https://api.enoki.mystenlabs.com"
    static let proverEndpoint = "\(proverBaseURL)/v1"  // Base endpoint with version
    static let zkLoginAPIEndpoint = "\(proverEndpoint)/zklogin/zkp"  // ZKP endpoint
    static let nonceEndpoint = "\(proverEndpoint)/zklogin/nonce"  // Nonce endpoint
    static let saltService = "\(proverEndpoint)/zklogin"  // Salt service
    static let networkTimeout: TimeInterval = 30
    
    // Ephemeral key configuration
    static let ephemeralKeyValidityInEpochs = 2  // Key valid for 2 epochs from current
    
    // Enoki specific configurations
    static let enokiPublicKey = "enoki_public_340d1143bcdc3990013f2e8f83c7930a"
    static let maxEpochDuration = 2  // Number of epochs the proof is valid for
    static let proofTimeout: TimeInterval = 30  // Timeout for proof generation
    
    // ZK Login specific endpoints
    static let proverPath = "/v1/zklogin/prove"  // Updated proof endpoint path
    static let saltPath = "/v1/get_salt"  // Salt retrieval endpoint
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
    let validUntilEpoch: Int
    
    init(validUntilEpoch: Int) {
        let privateKey = Curve25519.Signing.PrivateKey()
        self.privateKey = privateKey
        self.publicKey = privateKey.publicKey
        self.validUntilEpoch = validUntilEpoch
    }
} 