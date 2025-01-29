import Foundation

enum Constants {
    static let googleOAuthConfig = GoogleOAuthConfig(
        clientId: "211645280608-23hf7csv47gcbo6m5ntj2tlev0pj3qc6.apps.googleusercontent.com",
        redirectUri: "com.st.stack:/oauth2callback",
        scope: "email profile"
    )
    
    static let zkLoginAPIEndpoint = "https://zklogin-api.sui.io/proof"
}

struct GoogleOAuthConfig {
    let clientId: String
    let redirectUri: String
    let scope: String
    
    var authURL: URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "scope", value: scope)
        ]
        return components?.url
    }
} 