import SwiftUI
import AuthenticationServices

struct ContentView: View {
    @State private var isLoggedIn = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var accessToken: String?
    
    var body: some View {
        VStack(spacing: 20) {
            if isLoggedIn {
                Text("Welcome to zkLogin App")
                    .font(.title)
                    .padding()
                
                if let token = accessToken {
                    Text("Token: \(String(token.prefix(20)))...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Button("Logout") {
                    logout()
                }
                .buttonStyle(.borderedProminent)
                
            } else {
                Text("zkLogin Demo")
                    .font(.title)
                    .padding()
                
                Button("Login with Google") {
                    startGoogleOAuth()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func startGoogleOAuth() {
        guard let authURL = Constants.googleOAuthConfig.authURL else {
            showError("Invalid OAuth URL")
            return
        }
        
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: URL(string: Constants.googleOAuthConfig.redirectUri)?.scheme
        ) { callbackURL, error in
            if let error = error {
                showError(error.localizedDescription)
                return
            }
            
            guard let callbackURL = callbackURL,
                  let fragment = callbackURL.fragment else {
                showError("Invalid callback URL")
                return
            }
            
            let params = fragment
                .components(separatedBy: "&")
                .map { $0.components(separatedBy: "=") }
                .reduce(into: [String: String]()) { result, param in
                    if param.count == 2 {
                        result[param[0]] = param[1]
                    }
                }
            
            if let token = params["access_token"] {
                handleSuccessfulLogin(with: token)
            } else {
                showError("No access token found")
            }
        }
        
        session.presentationContextProvider = AuthContext.shared
        session.prefersEphemeralWebBrowserSession = true
        
        if !session.start() {
            showError("Could not start authentication session")
        }
    }
    
    private func handleSuccessfulLogin(with token: String) {
        Task {
            do {
                try await sendProofRequest(token: token)
                try KeychainManager.shared.saveToken(token)
                accessToken = token
                isLoggedIn = true
            } catch {
                showError(error.localizedDescription)
            }
        }
    }
    
    private func sendProofRequest(token: String) async throws {
        let data = try await NetworkManager.shared.sendZkLoginProofRequest(token: token)
        print("Received proof response:", String(data: data, encoding: .utf8) ?? "")
    }
    
    private func logout() {
        do {
            try KeychainManager.shared.deleteToken()
            accessToken = nil
            isLoggedIn = false
        } catch {
            showError(error.localizedDescription)
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

// MARK: - Authentication Context
class AuthContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthContext()
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return UIWindow()
        }
        return window
    }
} 