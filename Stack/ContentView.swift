//
//  ContentView.swift
//  Stack
//
//  Created by Malik Amine on 1/28/25.
//

import SwiftUI
import GoogleSignIn
import GoogleSignInSwift

#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @State private var isLoggedIn = false
    @State private var showingError = false
    @State private var errorMessage: String?
    @State private var accessToken: String?
    @State private var currentStep: OnboardingStep = .welcome
    @State private var currentPage = 0
    @State private var autoScrollTimer: Timer?
    @State private var isUserInteracting = false
    @State private var dragOffset: CGFloat = 0
    
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    private let slideTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    )
    
    // Carousel data
    private let carouselItems = [
        CarouselItem(
            icon: "shield.fill",
            title: "Secure Your Future",
            description: "Stack helps you build wealth securely with self-custodial crypto investments",
            color: Theme.primary,
            gradient: [Theme.primary, Theme.primary.opacity(0.6)]
        ),
        CarouselItem(
            icon: "chart.line.uptrend.xyaxis.circle.fill",
            title: "Smart Investing",
            description: "Get personalized portfolio recommendations based on your risk profile",
            color: Theme.accent,
            gradient: [Theme.accent, Theme.accent.opacity(0.6)]
        ),
        CarouselItem(
            icon: "key.fill",
            title: "You Own Your Keys",
            description: "Full control of your assets with our non-custodial wallet technology",
            color: Theme.secondary,
            gradient: [Theme.secondary, Theme.secondary.opacity(0.6)]
        ),
        CarouselItem(
            icon: "dollarsign.circle.fill",
            title: "Start Small, Grow Big",
            description: "Begin your investment journey with as little as $5",
            color: Theme.success,
            gradient: [Theme.success, Theme.success.opacity(0.6)]
        )
    ]
    
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
        VStack(spacing: 32) {
            // Carousel Section
            TabView(selection: $currentPage) {
                ForEach(0..<carouselItems.count, id: \.self) { index in
                    carouselSlide(carouselItems[index])
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .frame(height: 400)
            
            // Custom Page Indicators
            HStack(spacing: 12) {
                ForEach(0..<carouselItems.count, id: \.self) { index in
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: currentPage == index ? carouselItems[index].gradient : [Color.gray.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: currentPage == index ? 12 : 8, height: currentPage == index ? 12 : 8)
                        .scaleEffect(currentPage == index ? 1.2 : 1.0)
                        .overlay(
                            Circle()
                                .stroke(carouselItems[index].color.opacity(0.3), lineWidth: 1)
                                .scaleEffect(currentPage == index ? 1.4 : 0)
                                .opacity(currentPage == index ? 1 : 0)
                        )
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                        .onTapGesture {
                            hapticFeedback.impactOccurred(intensity: 0.7)
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                                currentPage = index
                            }
                        }
                }
            }
            .padding(.top, -20)
            
            Spacer()
            
            // Sign In Section
            VStack(spacing: 16) {
                // Google Sign In Button
                Button(action: startGoogleSignIn) {
                    HStack(spacing: 12) {
                        Image("google_logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        
                        Text("Continue with Google")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.1), radius: 8, x: 0, y: 4)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 1)
                    }
                }
                .buttonStyle(GoogleButtonStyle())
                
                // Test Button (Development Only)
                #if DEBUG
                Button(action: {
                    isLoggedIn = true
                    currentStep = .riskQuestionnaire
                }) {
                    Text("Skip Sign In (Test)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                // API Debug Button (Development Only)
                Button(action: {
                    Task {
                        print("\n🔍 Testing API endpoints...")
                        await NetworkManager.shared.checkApiStatus()
                        
                        // Generate a test salt
                        print("\n🔑 Testing salt generation...")
                        let testToken = "test.jwt.token"
                        let testNonce = "test_nonce_123"
                        let salt = NetworkManager.shared.generateLocalSaltForTesting(from: testToken, nonce: testNonce)
                        print("✅ Test salt generated: \(salt)")
                    }
                }) {
                    Text("Debug API")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                #endif
                
                // Terms Text
                Text("By continuing, you agree to our Terms of Service and Privacy Policy")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                startAutoScroll()
            }
            hapticFeedback.prepare()
        }
        .onDisappear {
            stopAutoScroll()
        }
    }
    
    private func carouselSlide(_ item: CarouselItem) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 24) {
                // Animated Icon Container
                Circle()
                    .fill(
                        LinearGradient(
                            colors: item.gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ).opacity(0.1)
                    )
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: item.icon)
                            .font(.system(size: 50, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: item.gradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolEffect(.bounce.up.byLayer, options: .repeating)
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: item.gradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ).opacity(0.3),
                                lineWidth: 2
                            )
                    )
                    .scaleEffect(currentPage == carouselItems.firstIndex(where: { $0.icon == item.icon }) ?? 0 ? 1.1 : 0.8)
                    .opacity(currentPage == carouselItems.firstIndex(where: { $0.icon == item.icon }) ?? 0 ? 1 : 0.5)
                    .blur(radius: currentPage == carouselItems.firstIndex(where: { $0.icon == item.icon }) ?? 0 ? 0 : 2)
                    .offset(y: currentPage == carouselItems.firstIndex(where: { $0.icon == item.icon }) ?? 0 ? 0 : 30)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.7), value: currentPage)
                
                VStack(spacing: 16) {
                    Text(item.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(Theme.text)
                        .scaleEffect(currentPage == carouselItems.firstIndex(where: { $0.icon == item.icon }) ?? 0 ? 1 : 0.8)
                        .opacity(currentPage == carouselItems.firstIndex(where: { $0.icon == item.icon }) ?? 0 ? 1 : 0)
                        .offset(y: currentPage == carouselItems.firstIndex(where: { $0.icon == item.icon }) ?? 0 ? 0 : 20)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2), value: currentPage)
                    
                    Text(item.description)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 32)
                        .scaleEffect(currentPage == carouselItems.firstIndex(where: { $0.icon == item.icon }) ?? 0 ? 1 : 0.8)
                        .opacity(currentPage == carouselItems.firstIndex(where: { $0.icon == item.icon }) ?? 0 ? 1 : 0)
                        .offset(y: currentPage == carouselItems.firstIndex(where: { $0.icon == item.icon }) ?? 0 ? 0 : 20)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3), value: currentPage)
                }
            }
            .frame(width: geometry.size.width)
            .rotation3DEffect(
                .degrees(dragOffset / 10),
                axis: (x: 0, y: 1, z: 0)
            )
        }
        .padding(.top, 20)
    }
    
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(Theme.primary)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
    
    private func startGoogleSignIn() {
        print("\n🚀 Starting Google Sign-In process...")
        
        guard let presentingViewController = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.rootViewController else {
            showError("Cannot find presenting view controller")
            return
        }
        
        Task {
            do {
                // Check API status first to identify any endpoint issues
                print("\n📡 Checking zkLogin API endpoint status...")
                let (workingCount, workingEndpoints) = await NetworkManager.shared.checkApiStatus()
                
                // Display information about working endpoints
                if workingCount == 0 {
                    print("⚠️ Warning: No zkLogin endpoints are currently available.")
                    print("The app will attempt to use fallback mechanisms to complete authentication.")
                } else {
                    print("✅ Found \(workingCount) working endpoints.")
                    
                    // Check if any proof endpoints are working
                    let workingProofEndpoint = workingEndpoints.first { $0.key.contains("proof") && $0.value }
                    if let (endpoint, _) = workingProofEndpoint {
                        print("✅ Working proof endpoint found: \(endpoint)")
                    } else {
                        print("⚠️ No working proof endpoints found. Authentication may not complete successfully.")
                    }
                }
                
                // Step 1: Configure Google Sign-In
                print("\n📝 Step 1: Configuring Google Sign-In...")
                let signInConfig = GIDConfiguration(
                    clientID: Constants.googleOAuthConfig.clientId,
                    serverClientID: nil,
                    hostedDomain: nil,
                    openIDRealm: nil
                )
                GIDSignIn.sharedInstance.configuration = signInConfig
                print("✅ Google Sign-In configured with client ID")
                
                // Step 2: Sign in with Google
                print("\n📝 Step 2: Starting Google Sign-In...")
                let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GIDSignInResult, Error>) in
                    GIDSignIn.sharedInstance.signIn(
                        withPresenting: presentingViewController
                    ) { signInResult, error in
                        if let error = error {
                            print("❌ Google Sign-In failed: \(error.localizedDescription)")
                            continuation.resume(throwing: error)
                            return
                        }
                        
                        guard let signInResult = signInResult else {
                            print("❌ No sign-in result received")
                            continuation.resume(throwing: NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No sign-in result"]))
                            return
                        }
                        
                        print("✅ Google Sign-In successful")
                        
                        // After getting the sign-in result, refresh tokens with nonce
                        print("\n📝 Refreshing tokens...")
                        signInResult.user.refreshTokensIfNeeded { user, error in
                            if let error = error {
                                print("❌ Token refresh failed: \(error.localizedDescription)")
                                continuation.resume(throwing: error)
                                return
                            }
                            print("✅ Tokens refreshed successfully")
                            continuation.resume(returning: signInResult)
                        }
                    }
                }
                
                // Step 4: Get ID token
                print("\n📝 Step 4: Getting ID token...")
                let user = result.user
                guard let idToken = user.idToken?.tokenString else {
                    print("❌ Failed to get ID token")
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get ID token"])
                }
                
                print("✅ Received ID Token:")
                print("First 50 chars: \(String(idToken.prefix(50)))...")
                print("Token length: \(idToken.count)")
                
                // Step 5: Decode JWT and extract nonce
                print("\n📝 Decoding JWT...")
                guard let decodedJWT = decodeJWT(token: idToken),
                      let jwtNonce = decodedJWT["nonce"] as? String else {
                    print("❌ Failed to decode JWT or extract nonce")
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode JWT or extract nonce"])
                }
                
                print("JWT Payload:")
                decodedJWT.forEach { key, value in
                    print("\(key): \(value)")
                }
                
                // Step 6: Create ephemeral key
                print("\n📝 Creating ephemeral key...")
                let ephemeralKey = try EphemeralKey(validUntilEpoch: 0)
                print("Generated ephemeral key: \(ephemeralKey.publicKeyBase64)")
                
                // Step 7: Get Enoki parameters using Google's nonce
                print("\n📝 Getting Enoki parameters...")
                let (randomness, maxEpoch) = try await NetworkManager.shared.getZkLoginParameters(ephemeralPublicKey: ephemeralKey.publicKeyBase64)
                print("Using JWT nonce: \(jwtNonce)")
                print("Randomness: \(randomness)")
                print("Max Epoch: \(maxEpoch)")
                
                // Step 5: Send proof request with the JWT
                print("\n📝 Step 5: Sending proof request...")
                print("⚠️ IMPORTANT: If the salt endpoint fails, a locally generated salt will be used as a fallback")
                print("This is less secure but allows the app to function when the API has changed")
                
                if workingCount == 0 {
                    print("\n⚠️ No working zkLogin endpoints were found. Using dynamic endpoint discovery...")
                    print("The app will try multiple endpoint combinations to complete authentication.")
                }
                
                let data = try await NetworkManager.shared.sendZkLoginProofRequest(
                    token: idToken,
                    nonce: jwtNonce,
                    randomness: randomness,
                    maxEpoch: maxEpoch,
                    publicKey: ephemeralKey.publicKeyBase64
                )
                
                // Handle successful proof
                try KeychainManager.shared.saveToken(idToken)
                accessToken = idToken
                isLoggedIn = true
                currentStep = .riskQuestionnaire
                
                print("\n✅ Sign-in process completed successfully!")
                print("Proof response:", String(data: data, encoding: .utf8) ?? "")
                
            } catch {
                print("\n❌ Error in sign-in process:")
                print("Error: \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    print("Domain: \(nsError.domain)")
                    print("Code: \(nsError.code)")
                    print("User Info: \(nsError.userInfo)")
                }
                
                // Check if it's a salt-related error and provide more helpful guidance
                if error.localizedDescription.contains("salt") {
                    let errorMessage = """
                    Authentication failed: Salt retrieval issue.
                    
                    The zkLogin API endpoints appear to have changed. The app tried multiple fallback options but was unable to complete authentication.
                    
                    Please try again later or check for app updates.
                    """
                    showError(errorMessage)
                } 
                // Check if it's a proof-related error
                else if error.localizedDescription.contains("proof") {
                    let errorMessage = """
                    Authentication failed: Proof generation issue.
                    
                    The zkLogin API endpoints appear to have changed. The app tried multiple fallback options but was unable to complete proof generation.
                    
                    Please try again later or check for app updates.
                    """
                    showError(errorMessage)
                }
                else {
                    showError(error.localizedDescription)
                }
            }
        }
    }
    
    private func decodeJWT(token: String) -> [String: Any]? {
        let segments = token.components(separatedBy: ".")
        guard segments.count == 3 else { return nil }
        
        func base64UrlDecode(_ value: String) -> Data? {
            var base64 = value
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            
            let padLength = 4 - base64.count % 4
            if padLength < 4 {
                base64 += String(repeating: "=", count: padLength)
            }
            
            return Data(base64Encoded: base64)
        }
        
        guard let payloadData = base64UrlDecode(segments[1]),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }
        
        return json
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
    
    private func startAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            if !isUserInteracting {
                withAnimation {
                    currentPage = (currentPage + 1) % carouselItems.count
                }
            }
        }
    }
    
    private func pauseAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }
    
    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }
}

#Preview {
    ContentView()
}

struct GoogleButtonStyle: ButtonStyle {
    @State private var isPressed = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.1 : 0.2),
                radius: configuration.isPressed ? 4 : 8,
                x: 0,
                y: configuration.isPressed ? 2 : 4
            )
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// Carousel Item Model
struct CarouselItem {
    let icon: String
    let title: String
    let description: String
    let color: Color
    let gradient: [Color]
}

// Parallax Motion Modifier
struct ParallaxMotion: ViewModifier {
    @State private var time: TimeInterval = 0
    let magnitude: Double
    
    func body(content: Content) -> some View {
        content
            .offset(
                x: CGFloat(sin(time * 2)) * magnitude / 2,
                y: CGFloat(cos(time * 2)) * magnitude / 2
            )
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: true)) {
                    time = 1
                }
            }
    }
}
