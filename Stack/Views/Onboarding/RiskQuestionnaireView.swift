import SwiftUI

struct RiskQuestionnaireView: View {
    @Binding var currentStep: ContentView.OnboardingStep
    @State private var currentQuestionIndex = 0
    @State private var answers: [Int] = []
    
    let questions = [
        "How long do you plan to hold your crypto investments?",
        "How would you react to a 20% drop in your portfolio value?",
        "What percentage of your total investments are you planning to allocate to crypto?",
        "Have you invested in cryptocurrencies before?"
    ]
    
    let options = [
        ["Less than 1 year", "1-3 years", "3-5 years", "More than 5 years"],
        ["Sell immediately", "Hold and wait", "Buy more at lower prices"],
        ["Less than 5%", "5-10%", "10-20%", "More than 20%"],
        ["Never", "Some experience", "Experienced trader"]
    ]
    
    var body: some View {
        VStack(spacing: 24) {
            ProgressView(value: Double(currentQuestionIndex), total: Double(questions.count))
                .padding(.horizontal)
            
            Text("Risk Assessment")
                .font(.title)
                .fontWeight(.bold)
            
            if currentQuestionIndex < questions.count {
                questionView
            } else {
                calculatingView
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    private var questionView: some View {
        VStack(spacing: 20) {
            Text(questions[currentQuestionIndex])
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding()
            
            ForEach(Array(options[currentQuestionIndex].enumerated()), id: \.offset) { index, option in
                Button(action: {
                    answers.append(index)
                    if currentQuestionIndex < questions.count - 1 {
                        currentQuestionIndex += 1
                    } else {
                        calculateRiskProfile()
                    }
                }) {
                    Text(option)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                }
            }
            
            // Test button for skipping questionnaire
            Button("Skip Questionnaire (Test)") {
                currentStep = .portfolioMatch
            }
            .padding()
            .buttonStyle(.bordered)
        }
    }
    
    private var calculatingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
            Text("Calculating your risk profile...")
                .padding()
        }
    }
    
    private func calculateRiskProfile() {
        // Simulate calculation delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            currentStep = .portfolioMatch
        }
    }
} 