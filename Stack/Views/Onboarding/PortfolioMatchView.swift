import SwiftUI

struct PortfolioMatchView: View {
    @Binding var currentStep: ContentView.OnboardingStep
    
    let recommendedPortfolio = [
        ("Bitcoin (BTC)", 0.50, Color.orange),
        ("Ethereum (ETH)", 0.30, Color.blue),
        ("Solana (SOL)", 0.15, Color.purple),
        ("USDC", 0.05, Color.green)
    ]
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Your Recommended Portfolio")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top)
            
            Text("Based on your risk profile, we recommend:")
                .foregroundColor(.secondary)
            
            VStack(spacing: 16) {
                ForEach(recommendedPortfolio, id: \.0) { asset, allocation, color in
                    HStack {
                        Circle()
                            .fill(color)
                            .frame(width: 12, height: 12)
                        
                        Text(asset)
                            .font(.headline)
                        
                        Spacer()
                        
                        Text("\(Int(allocation * 100))%")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
            
            VStack(spacing: 8) {
                Text("Risk Level: Moderate")
                    .font(.headline)
                
                Text("This portfolio balances growth potential with stability through a mix of established and emerging cryptocurrencies.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            
            Button(action: {
                currentStep = .mainApp
            }) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            
            // Test button for skipping portfolio match
            Button("Skip to App (Test)") {
                currentStep = .mainApp
            }
            .padding()
            .buttonStyle(.bordered)
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
    }
} 