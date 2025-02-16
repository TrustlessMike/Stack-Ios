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
    @State private var currentStep: OnboardingStep = .welcome
    
    enum OnboardingStep {
        case welcome
        case riskQuestionnaire
        case portfolioMatch
        case mainApp
    }
    
    var body: some View {
        Group {
            switch currentStep {
            case .welcome:
                welcomeView
            case .riskQuestionnaire:
                RiskQuestionnaireView(currentStep: $currentStep)
            case .portfolioMatch:
                PortfolioMatchView(currentStep: $currentStep)
            case .mainApp:
                MainTabView()
            }
        }
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
    
    private var welcomeView: some View {
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
                
                // Test button for skipping login
                Button("Skip Login (Test)") {
                    isLoggedIn = true
                    currentStep = .riskQuestionnaire
                }
                .padding()
                .buttonStyle(.bordered)
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
    }
    
    private func startGoogleSignIn() {
        guard let presentingViewController = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.rootViewController else {
            showError("Cannot find presenting view controller")
            return
        }
        
        Task {
            do {
                // Step 1: Create ephemeral key and get nonce from Enoki FIRST
                let ephemeralKey = try EphemeralKey(validUntilEpoch: 0)
                let (nonceFromEnoki, randomness, _, maxEpoch) = try await NetworkManager.shared.getNonce(ephemeralPublicKey: ephemeralKey.publicKeyBase64)
                
                // Step 2: Create the Google Sign-In URL with the correct nonce
                var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
                components?.queryItems = [
                    URLQueryItem(name: "client_id", value: Constants.googleOAuthConfig.clientId),
                    URLQueryItem(name: "redirect_uri", value: Constants.googleOAuthConfig.redirectUri),
                    URLQueryItem(name: "response_type", value: "id_token"),
                    URLQueryItem(name: "scope", value: "email profile openid"),
                    URLQueryItem(name: "nonce", value: nonceFromEnoki),  // Include Enoki's nonce
                    URLQueryItem(name: "prompt", value: "select_account")
                ]
                
                guard let authURL = components?.url else {
                    showError("Failed to create auth URL")
                    return
                }
                
                // Step 3: Start the auth session
                let scheme = Constants.googleOAuthConfig.redirectUri.components(separatedBy: ":/").first ?? ""
                
                let idToken: String = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                    let session = ASWebAuthenticationSession(
                        url: authURL,
                        callbackURLScheme: scheme
                    ) { callbackURL, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }
                        
                        guard let callbackURL = callbackURL,
                              let fragment = callbackURL.fragment else {
                            continuation.resume(throwing: NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid callback URL"]))
                            return
                        }
                        
                        // Parse the fragment to get the ID token
                        let params = fragment
                            .components(separatedBy: "&")
                            .map { $0.components(separatedBy: "=") }
                            .reduce(into: [String: String]()) { result, param in
                                if param.count == 2 {
                                    result[param[0]] = param[1].removingPercentEncoding
                                }
                            }
                        
                        if let idToken = params["id_token"] {
                            continuation.resume(returning: idToken)
                        } else {
                            continuation.resume(throwing: NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No ID token in response"]))
                        }
                    }
                    
                    session.presentationContextProvider = AuthContext.shared
                    session.prefersEphemeralWebBrowserSession = true
                    
                    if !session.start() {
                        continuation.resume(throwing: NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start auth session"]))
                    }
                }
                
                // Step 4: Send proof request with the JWT that contains the correct nonce
                let data = try await NetworkManager.shared.sendZkLoginProofRequest(
                    token: idToken,
                    nonce: nonceFromEnoki,
                    randomness: randomness,
                    maxEpoch: maxEpoch,
                    publicKey: ephemeralKey.publicKeyBase64
                )
                
                // Handle successful proof
                try KeychainManager.shared.saveToken(idToken)
                accessToken = idToken
                isLoggedIn = true
                currentStep = .riskQuestionnaire
                
                print("Received proof response:", String(data: data, encoding: .utf8) ?? "")
                
            } catch {
                showError(error.localizedDescription)
            }
        }
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
