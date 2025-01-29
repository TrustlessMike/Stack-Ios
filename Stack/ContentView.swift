//
//  ContentView.swift
//  Stack
//
//  Created by Malik Amine on 1/28/25.
//

import SwiftUI
import GoogleSignIn
import GoogleSignInSwift
import AuthenticationServices

#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @State private var isLoggedIn = false
    @State private var showingError = false
    @State private var errorMessage: String?
    @State private var accessToken: String?
    
    var body: some View {
        VStack(spacing: 20) {
            if !isLoggedIn {
                Text("Welcome to Stack")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.primary)
                    .padding(.top, 40)
                
                Text("Sign In")
                    .font(.title)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 20)
                
                Button(action: startGoogleSignIn) {
                    HStack(spacing: 12) {
                        Image("google_logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        
                        Text("Continue with Google")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.1), radius: 5, x: 0, y: 2)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 1)
                    }
                }
                .padding(.horizontal, 24)
                .buttonStyle(GoogleButtonStyle())
            } else {
                Text("Welcome Back!")
                    .font(.system(size: 34, weight: .bold))
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
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {
                errorMessage = nil
                showingError = false
            }
        } message: {
            if let message = errorMessage {
                Text(message)
            }
        }
    }
    
    private func startGoogleSignIn() {
        guard let presentingViewController = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.rootViewController else {
            showError("Cannot find presenting view controller")
            return
        }
        
        let config = GIDConfiguration(clientID: Constants.googleOAuthConfig.clientId)
        GIDSignIn.sharedInstance.configuration = config
        
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
            if let error = error {
                showError(error.localizedDescription)
                return
            }
            
            guard let result = result,
                  let idToken = result.user.idToken?.tokenString else {
                showError("Failed to get ID token")
                return
            }
            
            handleSuccessfulLogin(with: idToken)
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
        GIDSignIn.sharedInstance.signOut()
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
            fatalError("No window found for iOS platform")
        }
        return window
    }
}

#Preview {
    ContentView()
}

struct GoogleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}
