import SwiftUI

enum Theme {
    // Brand Colors
    static let primary = Color("Primary")
    static let secondary = Color("Secondary")
    static let accent = Color("Accent")
    
    // Semantic Colors
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    
    // Crypto Asset Colors
    static let bitcoin = Color(hex: "#F7931A")
    static let ethereum = Color(hex: "#627EEA")
    static let solana = Color(hex: "#9945FF")
    static let usdc = Color(hex: "#2775CA")
    
    // Background Colors
    static let background = Color(.systemBackground)
    static let secondaryBackground = Color(.secondarySystemBackground)
    static let groupedBackground = Color(.systemGroupedBackground)
    
    // Text Colors
    static let text = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    
    // Card Style
    static func cardStyle<V: View>(_ content: V) -> some View {
        content
            .padding()
            .background(Theme.background)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
    
    // Button Styles
    static func primaryButtonStyle<V: View>(_ content: V) -> some View {
        content
            .padding()
            .frame(maxWidth: .infinity)
            .background(Theme.primary)
            .foregroundColor(.white)
            .cornerRadius(12)
            .shadow(color: Theme.primary.opacity(0.3), radius: 8, x: 0, y: 4)
    }
    
    static func secondaryButtonStyle<V: View>(_ content: V) -> some View {
        content
            .padding()
            .frame(maxWidth: .infinity)
            .background(Theme.secondaryBackground)
            .foregroundColor(Theme.text)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(.separator), lineWidth: 1)
            )
    }
    
    // Text Styles
    static func titleStyle(_ text: Text) -> some View {
        text
            .font(.system(size: 34, weight: .bold))
            .foregroundColor(Theme.text)
    }
    
    static func headlineStyle(_ text: Text) -> some View {
        text
            .font(.headline)
            .foregroundColor(Theme.text)
    }
    
    static func bodyStyle(_ text: Text) -> some View {
        text
            .font(.body)
            .foregroundColor(Theme.text)
    }
    
    static func captionStyle(_ text: Text) -> some View {
        text
            .font(.caption)
            .foregroundColor(Theme.secondaryText)
    }
}

// Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
} 