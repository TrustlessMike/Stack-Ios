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
    
    // Prover service endpoints
    static let proverBaseURL = "https://prover.mystenlabs.com"  // Remove /v1 from base
    static let proverEndpoint = "\(proverBaseURL)/zklogin"  // zkLogin specific endpoint
    static let zkLoginAPIEndpoint = proverEndpoint  // Keep consistent
    static let saltService = "https://salt.mystenlabs.com/v1/get_salt"
    static let networkTimeout: TimeInterval = 30
    
    // Ephemeral key configuration
    static let ephemeralKeyValidityInEpochs = 2  // Key valid for 2 epochs from current
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