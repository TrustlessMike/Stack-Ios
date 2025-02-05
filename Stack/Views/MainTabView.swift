import SwiftUI
import Kingfisher

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Portfolio", systemImage: "chart.pie.fill")
                }
                .tag(0)
            
            PersonalView()
                .tabItem {
                    Label("Personal", systemImage: "person.fill")
                }
                .tag(1)
            
            BankingView()
                .tabItem {
                    Label("Banking", systemImage: "dollarsign.circle.fill")
                }
                .tag(2)
            
            LearnView()
                .tabItem {
                    Label("Learn", systemImage: "book.fill")
                }
                .tag(3)
        }
        .tint(Theme.primary)
    }
}

struct DashboardView: View {
    @State private var portfolioValue: Double = 1250.75
    @State private var totalGain: Double = 125.50
    @State private var gainPercentage: Double = 11.2
    @State private var showingNotifications = false
    @State private var isRefreshing = false
    @State private var isLoading = false
    @State private var selectedTimeRange = "1D"
    @State private var selectedFilter = "All"
    @State private var sortOrder: SortOrder = .value
    
    enum SortOrder {
        case value
        case gains
        case name
    }
    
    let timeRanges = ["1D", "1W", "1M", "1Y", "ALL"]
    
    private var sortedAssets: [(String, String, String, Color)] {
        let filtered = selectedFilter == "All" ? assets :
            selectedFilter == "Stablecoins" ? assets.filter { $0.0.contains("USDC") } :
            assets.filter { !$0.0.contains("USDC") }
        
        switch sortOrder {
        case .value:
            return filtered.sorted {
                let value1 = Double($0.1.replacingOccurrences(of: "$", with: "")) ?? 0
                let value2 = Double($1.1.replacingOccurrences(of: "$", with: "")) ?? 0
                return value1 > value2
            }
        case .gains:
            return filtered.sorted {
                let gain1 = Double($0.2.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")) ?? 0
                let gain2 = Double($1.2.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")) ?? 0
                return gain1 > gain2
            }
        case .name:
            return filtered.sorted { $0.0 < $1.0 }
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    portfolioCard
                    chartCard
                    assetList
                }
                .padding(.vertical)
            }
            .background(Theme.groupedBackground)
            .navigationTitle("Portfolio")
            .navigationBarItems(trailing: notificationButton)
            .refreshable {
                await refreshDataAsync()
            }
        }
        .sheet(isPresented: $showingNotifications) {
            NotificationsView(showingNotifications: $showingNotifications)
        }
    }
    
    private var portfolioCard: some View {
        Theme.cardStyle(
            VStack(spacing: 8) {
                Text("Portfolio Value")
                    .font(.subheadline)
                    .foregroundColor(Theme.secondaryText)
                
                if isLoading {
                    Text("$1,250.75")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(Theme.text)
                        .redacted(reason: .placeholder)
                } else {
                    Text("$\(portfolioValue, specifier: "%.2f")")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(Theme.text)
                        .contentTransition(.numericText())
                }
                
                portfolioGains
                timeRangeSelector
            }
        )
        .padding(.horizontal)
        .transition(.scale.combined(with: .opacity))
    }
    
    private var portfolioGains: some View {
        HStack(spacing: 12) {
            Image(systemName: gainPercentage >= 0 ? "arrow.up.right" : "arrow.down.right")
                .foregroundColor(gainPercentage >= 0 ? Theme.success : Theme.error)
                .symbolEffect(.bounce, value: gainPercentage)
            
            Group {
                if isLoading {
                    Text("$125.50")
                        .redacted(reason: .placeholder)
                } else {
                    Text("$\(abs(totalGain), specifier: "%.2f")")
                        .contentTransition(.numericText())
                }
            }
            .foregroundColor(gainPercentage >= 0 ? Theme.success : Theme.error)
            
            Group {
                if isLoading {
                    Text("(11.2%)")
                        .redacted(reason: .placeholder)
                } else {
                    Text("(\(abs(gainPercentage), specifier: "%.1f")%)")
                        .contentTransition(.numericText())
                }
            }
            .foregroundColor(gainPercentage >= 0 ? Theme.success : Theme.error)
        }
        .font(.headline)
    }
    
    private var timeRangeSelector: some View {
        HStack(spacing: 8) {
            ForEach(timeRanges, id: \.self) { range in
                timeRangeButton(range)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(Theme.secondaryBackground.opacity(0.5))
        .cornerRadius(12)
    }
    
    private func timeRangeButton(_ range: String) -> some View {
        Button(action: {
            withAnimation { selectedTimeRange = range }
            refreshData()
        }) {
            Text(range)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    selectedTimeRange == range ?
                    Theme.primary : Color.clear
                )
                .foregroundColor(
                    selectedTimeRange == range ?
                    .white : Theme.secondaryText
                )
                .cornerRadius(8)
        }
    }
    
    private var chartCard: some View {
        Theme.cardStyle(
            VStack {
                timeRangeSelector
                
                if isLoading {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                            .frame(height: 150)
                    }
                } else {
                    chartView
                }
            }
            .padding()
        )
        .padding(.horizontal)
    }
    
    private var chartView: some View {
        GeometryReader { geometry in
            ZStack {
                // Grid lines
                VStack(spacing: geometry.size.height / 4) {
                    ForEach(0..<4) { _ in
                        Divider()
                            .background(Theme.secondaryText.opacity(0.2))
                    }
                }
                
                // Price labels
                VStack(spacing: geometry.size.height / 4) {
                    ForEach(["$2000", "$1500", "$1000", "$500"], id: \.self) { price in
                        Text(price)
                            .font(.caption2)
                            .foregroundColor(Theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, 8)
                
                // Chart line
                Path { path in
                    let width = geometry.size.width - 40 // Account for price labels
                    let height = geometry.size.height
                    let points = [
                        CGPoint(x: 0, y: height * 0.5),
                        CGPoint(x: width * 0.2, y: height * 0.4),
                        CGPoint(x: width * 0.4, y: height * 0.7),
                        CGPoint(x: width * 0.6, y: height * 0.3),
                        CGPoint(x: width * 0.8, y: height * 0.5),
                        CGPoint(x: width, y: height * 0.2)
                    ]
                    
                    path.move(to: points[0])
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [Theme.primary, Theme.primary.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: Theme.primary.opacity(0.3), radius: 4, x: 0, y: 2)
                .padding(.leading, 40) // Make space for price labels
                
                // Area under the line
                Path { path in
                    let width = geometry.size.width - 40
                    let height = geometry.size.height
                    let points = [
                        CGPoint(x: 0, y: height * 0.5),
                        CGPoint(x: width * 0.2, y: height * 0.4),
                        CGPoint(x: width * 0.4, y: height * 0.7),
                        CGPoint(x: width * 0.6, y: height * 0.3),
                        CGPoint(x: width * 0.8, y: height * 0.5),
                        CGPoint(x: width, y: height * 0.2)
                    ]
                    
                    path.move(to: CGPoint(x: 0, y: height))
                    path.addLine(to: points[0])
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                    path.addLine(to: CGPoint(x: width, y: height))
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Theme.primary.opacity(0.2),
                            Theme.primary.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(.leading, 40)
            }
        }
        .frame(height: 150)
        .animation(.easeInOut, value: selectedTimeRange)
    }
    
    private var assetList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Theme.headlineStyle(Text("Your Assets"))
                Spacer()
                Menu {
                    Button(action: { sortOrder = .value }) {
                        Label("Sort by Value", systemImage: "dollarsign.circle")
                    }
                    Button(action: { sortOrder = .gains }) {
                        Label("Sort by Gains", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    Button(action: { sortOrder = .name }) {
                        Label("Sort by Name", systemImage: "textformat.abc")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundColor(Theme.primary)
                }
                Button(action: refreshData) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(Theme.primary)
                        .symbolEffect(.bounce, value: isRefreshing)
                }
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(["All", "Crypto", "Stablecoins"], id: \.self) { filter in
                        filterButton(filter)
                    }
                }
                .padding(.horizontal)
            }
            
            ForEach(sortedAssets, id: \.0) { asset in
                AssetRow(asset: asset, isLoading: isLoading)
            }
        }
    }
    
    private var assets: [(String, String, String, Color)] {
        [
            ("Bitcoin (BTC)", "$750.00", "+5.2%", Theme.bitcoin),
            ("Ethereum (ETH)", "$375.00", "+3.8%", Theme.ethereum),
            ("Solana (SOL)", "$187.50", "+7.1%", Theme.solana),
            ("USDC", "$62.50", "+0.1%", Theme.usdc),
            ("Cardano (ADA)", "$125.30", "+2.8%", Color(hex: "#0033AD")),
            ("Polkadot (DOT)", "$98.75", "-1.2%", Color(hex: "#E6007A")),
            ("Avalanche (AVAX)", "$156.20", "+4.5%", Color(hex: "#E84142")),
            ("Chainlink (LINK)", "$82.40", "+3.1%", Color(hex: "#2A5ADA"))
        ]
    }
    
    private var notificationButton: some View {
        Button(action: { showingNotifications.toggle() }) {
            Image(systemName: "bell.fill")
                .foregroundColor(Theme.primary)
                .overlay(
                    Circle()
                        .fill(Theme.error)
                        .frame(width: 8, height: 8)
                        .offset(x: 8, y: -8)
                        .opacity(0.8)
                )
        }
    }
    
    private func refreshData() {
        withAnimation {
            isLoading = true
            isRefreshing = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                isLoading = false
                isRefreshing = false
                portfolioValue *= 1.02
                totalGain *= 1.05
                gainPercentage *= 1.01
            }
        }
    }
    
    private func refreshDataAsync() async {
        withAnimation {
            isLoading = true
            isRefreshing = true
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await MainActor.run {
            withAnimation {
                isLoading = false
                isRefreshing = false
                portfolioValue *= 1.02
                totalGain *= 1.05
                gainPercentage *= 1.01
            }
        }
    }
    
    private func filterButton(_ filter: String) -> some View {
        Button(action: {
            withAnimation {
                selectedFilter = filter
            }
        }) {
            Text(filter)
                .font(.footnote)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selectedFilter == filter ? Theme.primary : Theme.secondaryBackground)
                .foregroundColor(selectedFilter == filter ? .white : Theme.text)
                .cornerRadius(20)
        }
    }
}

struct AssetRow: View {
    let asset: (String, String, String, Color)
    let isLoading: Bool
    
    var body: some View {
        Theme.cardStyle(
            HStack(spacing: 16) {
                // Coinbase-style icon
                KFImage(URL(string: cryptoIconURL(for: asset.0)))
                    .placeholder {
                        Image(systemName: cryptoIcon(for: asset.0))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundColor(asset.3)
                    }
                    .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 40, height: 40)))
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(asset.0.components(separatedBy: "(").first ?? "")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Theme.text)
                        
                        Text(asset.0.components(separatedBy: "(").last?
                            .replacingOccurrences(of: ")", with: "") ?? "")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.secondaryText)
                    }
                    
                    Text("Market Value")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if isLoading {
                        Text(asset.1)
                            .redacted(reason: .placeholder)
                        Text(asset.2)
                            .redacted(reason: .placeholder)
                    } else {
                        Text(asset.1)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Theme.text)
                            .contentTransition(.numericText())
                        
                        Text(asset.2)
                            .font(.system(size: 15))
                            .foregroundColor(asset.2.hasPrefix("-") ? Theme.error : Theme.success)
                            .contentTransition(.numericText())
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        )
        .padding(.horizontal)
    }
    
    private func cryptoIconURL(for asset: String) -> String {
        let symbol = asset.components(separatedBy: "(").last?
            .replacingOccurrences(of: ")", with: "")
            .lowercased() ?? ""
            
        // Using higher quality images from CoinGecko
        switch symbol {
        case "btc":
            return "https://assets.coingecko.com/coins/images/1/large/bitcoin.png"
        case "eth":
            return "https://assets.coingecko.com/coins/images/279/large/ethereum.png"
        case "sol":
            return "https://assets.coingecko.com/coins/images/4128/large/solana.png"
        case "usdc":
            return "https://assets.coingecko.com/coins/images/6319/large/USD_Coin_icon.png"
        case "ada":
            return "https://assets.coingecko.com/coins/images/975/large/cardano.png"
        case "dot":
            return "https://assets.coingecko.com/coins/images/12171/large/polkadot.png"
        case "avax":
            return "https://assets.coingecko.com/coins/images/12559/large/Avalanche_Circle_RedWhite_Trans.png"
        case "link":
            return "https://assets.coingecko.com/coins/images/877/large/chainlink-new-logo.png"
        default:
            return ""
        }
    }
    
    private func cryptoIcon(for asset: String) -> String {
        if asset.contains("Bitcoin") { return "bitcoinsign.circle" }
        if asset.contains("Ethereum") { return "e.circle" }
        if asset.contains("Solana") { return "s.circle" }
        if asset.contains("USDC") { return "dollarsign.circle" }
        if asset.contains("Cardano") { return "a.circle" }
        if asset.contains("Polkadot") { return "d.circle" }
        if asset.contains("Avalanche") { return "a.circle" }
        if asset.contains("Chainlink") { return "link.circle" }
        return "questionmark.circle"
    }
}

struct NotificationsView: View {
    @Binding var showingNotifications: Bool
    
    var body: some View {
        NavigationView {
            List {
                ForEach(1...3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Price Alert")
                            .font(.headline)
                        Text("Bitcoin is up 5% in the last hour")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarItems(trailing: Button("Done") {
                showingNotifications = false
            })
        }
    }
}

struct PersonalView: View {
    var body: some View {
        NavigationView {
            Text("Personal View - Coming Soon")
                .navigationTitle("Personal")
        }
    }
}

struct BankingView: View {
    var body: some View {
        NavigationView {
            Text("Banking View - Coming Soon")
                .navigationTitle("Banking")
        }
    }
}

struct LearnView: View {
    var body: some View {
        NavigationView {
            Text("Learn View - Coming Soon")
                .navigationTitle("Learn")
        }
    }
}

#Preview {
    MainTabView()
} 