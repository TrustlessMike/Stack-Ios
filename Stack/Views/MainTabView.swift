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
    @State private var userName = "Yacob"
    @State private var profileImage: Image?
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            List {
                // Profile Section
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .foregroundColor(Theme.primary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(userName)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Verified Account")
                                .font(.subheadline)
                                .foregroundColor(Theme.success)
                        }
                        
                        Spacer()
                        
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gear")
                                .font(.title2)
                                .foregroundColor(Theme.primary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Account Security
                Section(header: Text("Security")) {
                    NavigationLink(destination: Text("2FA Settings")) {
                        Label("Two-Factor Authentication", systemImage: "lock.shield")
                    }
                    
                    NavigationLink(destination: Text("Recovery Settings")) {
                        Label("Recovery Phrase", systemImage: "key")
                    }
                    
                    NavigationLink(destination: Text("Device Management")) {
                        Label("Connected Devices", systemImage: "iphone")
                    }
                }
                
                // Wallet Management
                Section(header: Text("Wallet")) {
                    NavigationLink(destination: Text("Wallet Details")) {
                        Label("Wallet Address", systemImage: "wallet.pass")
                    }
                    
                    NavigationLink(destination: Text("Transaction History")) {
                        Label("Transaction History", systemImage: "clock.arrow.circlepath")
                    }
                    
                    NavigationLink(destination: Text("Network Settings")) {
                        Label("Network Settings", systemImage: "network")
                    }
                }
                
                // Preferences
                Section(header: Text("Preferences")) {
                    NavigationLink(destination: Text("Notification Settings")) {
                        Label("Notifications", systemImage: "bell")
                    }
                    
                    NavigationLink(destination: Text("Currency Settings")) {
                        Label("Currency", systemImage: "dollarsign.circle")
                    }
                    
                    NavigationLink(destination: Text("App Theme")) {
                        Label("Appearance", systemImage: "paintbrush")
                    }
                }
                
                // Support
                Section(header: Text("Support")) {
                    NavigationLink(destination: Text("Help Center")) {
                        Label("Help Center", systemImage: "questionmark.circle")
                    }
                    
                    NavigationLink(destination: Text("Contact Support")) {
                        Label("Contact Support", systemImage: "message")
                    }
                    
                    Link(destination: URL(string: "https://stack.com/privacy")!) {
                        Label("Privacy Policy", systemImage: "doc.text")
                    }
                }
                
                // Danger Zone
                Section {
                    Button(action: {}) {
                        Label("Sign Out", systemImage: "arrow.right.square")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Account")
        }
    }
}

struct BankingView: View {
    @State private var showingAddAccount = false
    @State private var showingTransfer = false
    @State private var selectedAccount: BankAccount?
    @State private var accounts: [BankAccount] = [
        BankAccount(name: "Main Checking", type: .checking, balance: 2500.00, lastFour: "4567"),
        BankAccount(name: "Savings", type: .savings, balance: 10000.00, lastFour: "8901")
    ]
    
    var body: some View {
        NavigationView {
            List {
                // Connected Accounts
                Section(header: Text("Connected Accounts")) {
                    ForEach(accounts) { account in
                        BankAccountRow(account: account)
                            .onTapGesture {
                                selectedAccount = account
                            }
                    }
                    
                    Button(action: { showingAddAccount = true }) {
                        Label("Add Bank Account", systemImage: "plus.circle")
                            .foregroundColor(Theme.primary)
                    }
                }
                
                // Quick Actions
                Section(header: Text("Quick Actions")) {
                    Button(action: { showingTransfer = true }) {
                        Label("Transfer Money", systemImage: "arrow.left.arrow.right")
                    }
                    
                    NavigationLink(destination: Text("Scheduled Transfers")) {
                        Label("Scheduled Transfers", systemImage: "calendar")
                    }
                    
                    NavigationLink(destination: Text("Transfer Limits")) {
                        Label("Transfer Limits", systemImage: "gauge")
                    }
                }
                
                // Recent Activity
                Section(header: Text("Recent Activity")) {
                    ForEach(0..<3) { _ in
                        TransactionRow()
                    }
                    
                    NavigationLink(destination: Text("All Transactions")) {
                        Text("View All Transactions")
                            .foregroundColor(Theme.primary)
                    }
                }
            }
            .navigationTitle("Banking")
            .sheet(isPresented: $showingAddAccount) {
                AddBankAccountView()
            }
            .sheet(isPresented: $showingTransfer) {
                TransferView(accounts: accounts)
            }
            .sheet(item: $selectedAccount) { account in
                AccountDetailView(account: account)
            }
        }
    }
}

struct BankAccount: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let type: AccountType
    let balance: Double
    let lastFour: String
    
    enum AccountType: Equatable {
        case checking
        case savings
    }
    
    static func == (lhs: BankAccount, rhs: BankAccount) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.type == rhs.type &&
        lhs.balance == rhs.balance &&
        lhs.lastFour == rhs.lastFour
    }
}

struct BankAccountRow: View {
    let account: BankAccount
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.headline)
                Text("••••\(account.lastFour)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("$\(account.balance, specifier: "%.2f")")
                .font(.headline)
                .foregroundColor(Theme.primary)
        }
        .padding(.vertical, 8)
    }
}

struct TransactionRow: View {
    var body: some View {
        HStack {
            Circle()
                .fill(Theme.secondaryBackground)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "arrow.down")
                        .foregroundColor(Theme.primary)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Deposit")
                    .font(.headline)
                Text("Today")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("$500.00")
                .font(.headline)
                .foregroundColor(Theme.success)
        }
        .padding(.vertical, 8)
    }
}

struct TransferView: View {
    @Environment(\.dismiss) var dismiss
    let accounts: [BankAccount]
    @State private var fromAccount: BankAccount?
    @State private var toAccount: BankAccount?
    @State private var amount: String = ""
    @State private var note: String = ""
    @State private var showingConfirmation = false
    @State private var transferDate = Date()
    @State private var isRecurring = false
    @State private var recurringFrequency = "Monthly"
    
    private let frequencies = ["Weekly", "Bi-weekly", "Monthly"]
    
    var body: some View {
        NavigationView {
            Form {
                amountSection
                fromAccountSection
                toAccountSection
                transferDetailsSection
                transferButtonSection
            }
            .navigationTitle("Transfer")
            .navigationBarItems(trailing: Button("Cancel") { dismiss() })
            .alert("Confirm Transfer", isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Transfer") {
                    // Perform transfer
                    dismiss()
                }
            } message: {
                Text("Transfer $\(amount) from \(fromAccount?.name ?? "") to \(toAccount?.name ?? "")?")
            }
        }
    }
    
    private var amountSection: some View {
        Section {
            HStack {
                Text("$")
                    .foregroundColor(.secondary)
                TextField("0.00", text: $amount)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 34, weight: .bold))
            }
            .padding(.vertical, 8)
        }
    }
    
    private var fromAccountSection: some View {
        Section(header: Text("From")) {
            ForEach(accounts) { account in
                AccountSelectionRow(
                    account: account,
                    isSelected: fromAccount == account,
                    action: { fromAccount = account }
                )
            }
        }
    }
    
    private var toAccountSection: some View {
        Section(header: Text("To")) {
            ForEach(accounts) { account in
                if account != fromAccount {
                    AccountSelectionRow(
                        account: account,
                        isSelected: toAccount == account,
                        action: { toAccount = account }
                    )
                }
            }
        }
    }
    
    private var transferDetailsSection: some View {
        Section(header: Text("Details")) {
            DatePicker("Transfer Date", selection: $transferDate, displayedComponents: [.date])
            
            Toggle("Recurring Transfer", isOn: $isRecurring)
            
            if isRecurring {
                Picker("Frequency", selection: $recurringFrequency) {
                    ForEach(frequencies, id: \.self) { frequency in
                        Text(frequency).tag(frequency)
                    }
                }
            }
            
            TextField("Add a note", text: $note)
        }
    }
    
    private var transferButtonSection: some View {
        Section {
            Button(action: { showingConfirmation = true }) {
                Text("Transfer")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canTransfer ? Theme.primary : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!canTransfer)
        }
        .listRowBackground(Color.clear)
    }
    
    private var canTransfer: Bool {
        fromAccount != nil &&
        toAccount != nil &&
        fromAccount != toAccount &&
        !amount.isEmpty &&
        (Double(amount) ?? 0) > 0
    }
}

struct AccountSelectionRow: View {
    let account: BankAccount
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name)
                        .font(.headline)
                    Text("Balance: $\(account.balance, specifier: "%.2f")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.primary)
                }
            }
        }
        .foregroundColor(.primary)
    }
}

struct AddBankAccountView: View {
    @Environment(\.dismiss) var dismiss
    @State private var accountName = ""
    @State private var accountType: BankAccount.AccountType = .checking
    @State private var routingNumber = ""
    @State private var accountNumber = ""
    @State private var confirmAccountNumber = ""
    @State private var showingConfirmation = false
    @State private var isVerifying = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Account Information")) {
                    TextField("Account Name", text: $accountName)
                    
                    Picker("Account Type", selection: $accountType) {
                        Text("Checking").tag(BankAccount.AccountType.checking)
                        Text("Savings").tag(BankAccount.AccountType.savings)
                    }
                }
                
                Section(header: Text("Bank Information")) {
                    SecureField("Routing Number", text: $routingNumber)
                        .keyboardType(.numberPad)
                    
                    SecureField("Account Number", text: $accountNumber)
                        .keyboardType(.numberPad)
                    
                    SecureField("Confirm Account Number", text: $confirmAccountNumber)
                        .keyboardType(.numberPad)
                }
                
                Section {
                    Button(action: verifyAccount) {
                        if isVerifying {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Add Account")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(canAddAccount ? Theme.primary : Color.gray)
                                .cornerRadius(12)
                        }
                    }
                    .disabled(!canAddAccount || isVerifying)
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Add Account")
            .navigationBarItems(trailing: Button("Cancel") { dismiss() })
            .alert("Account Added", isPresented: $showingConfirmation) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your bank account has been successfully added.")
            }
        }
    }
    
    private var canAddAccount: Bool {
        !accountName.isEmpty &&
        routingNumber.count == 9 &&
        accountNumber.count >= 8 &&
        accountNumber == confirmAccountNumber
    }
    
    private func verifyAccount() {
        isVerifying = true
        
        // Simulate verification process
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isVerifying = false
            showingConfirmation = true
        }
    }
}

struct AccountDetailView: View {
    @Environment(\.dismiss) var dismiss
    let account: BankAccount
    @State private var showingTransferSheet = false
    @State private var selectedTimeRange = "1M"
    @State private var transactions = [
        ("Deposit", "Yesterday", 1500.00, true),
        ("Withdrawal", "3 days ago", 200.00, false),
        ("Transfer", "1 week ago", 500.00, false)
    ]
    
    private let timeRanges = ["1W", "1M", "3M", "1Y", "ALL"]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Balance Card
                VStack(spacing: 8) {
                    Text("Current Balance")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("$\(account.balance, specifier: "%.2f")")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(Theme.text)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Theme.secondaryBackground)
                .cornerRadius(16)
                .padding(.horizontal)
                
                // Quick Actions
                HStack(spacing: 16) {
                    QuickActionButton(
                        title: "Transfer",
                        icon: "arrow.left.arrow.right",
                        action: { showingTransferSheet = true }
                    )
                    
                    QuickActionButton(
                        title: "Statements",
                        icon: "doc.text",
                        action: {}
                    )
                    
                    QuickActionButton(
                        title: "Settings",
                        icon: "gear",
                        action: {}
                    )
                }
                .padding(.horizontal)
                
                // Time Range Selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(timeRanges, id: \.self) { range in
                            Button(action: { selectedTimeRange = range }) {
                                Text(range)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        selectedTimeRange == range ?
                                            Theme.primary : Theme.secondaryBackground
                                    )
                                    .foregroundColor(
                                        selectedTimeRange == range ?
                                            .white : Theme.text
                                    )
                                    .cornerRadius(20)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Transactions
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recent Transactions")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ForEach(transactions, id: \.1) { transaction in
                        TransactionDetailRow(
                            type: transaction.0,
                            date: transaction.1,
                            amount: transaction.2,
                            isDeposit: transaction.3
                        )
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationBarItems(trailing: Button("Done") { dismiss() })
        .sheet(isPresented: $showingTransferSheet) {
            TransferView(accounts: [account])
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Theme.secondaryBackground)
            .cornerRadius(12)
        }
        .foregroundColor(Theme.text)
    }
}

struct TransactionDetailRow: View {
    let type: String
    let date: String
    let amount: Double
    let isDeposit: Bool
    
    var body: some View {
        HStack {
            Circle()
                .fill(Theme.secondaryBackground)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: isDeposit ? "arrow.down" : "arrow.up")
                        .foregroundColor(isDeposit ? Theme.success : Theme.primary)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(type)
                    .font(.headline)
                Text(date)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(isDeposit ? "+$\(amount, specifier: "%.2f")" : "-$\(amount, specifier: "%.2f")")
                .font(.headline)
                .foregroundColor(isDeposit ? Theme.success : Theme.text)
        }
        .padding()
        .background(Theme.background)
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct LearnView: View {
    @State private var selectedCategory: LearningCategory = .basics
    
    enum LearningCategory: String, CaseIterable {
        case basics = "Basics"
        case trading = "Trading"
        case defi = "DeFi"
        case security = "Security"
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Category Selector
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(LearningCategory.allCases, id: \.self) { category in
                                CategoryButton(
                                    title: category.rawValue,
                                    isSelected: category == selectedCategory,
                                    action: { selectedCategory = category }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Featured Course
                    FeaturedCourseCard()
                    
                    // Course List
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Popular Courses")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(0..<4) { _ in
                            CourseRow()
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Learn")
        }
    }
}

struct CategoryButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : Theme.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Theme.primary : Theme.primary.opacity(0.1))
                )
        }
    }
}

struct FeaturedCourseCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Featured")
                .font(.subheadline)
                .foregroundColor(Theme.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.primary.opacity(0.1))
                .cornerRadius(8)
            
            Text("Crypto Basics 101")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Learn the fundamentals of cryptocurrency and blockchain technology")
                .foregroundColor(.secondary)
            
            HStack {
                Label("12 Lessons", systemImage: "book.closed")
                Spacer()
                Label("2.5 Hours", systemImage: "clock")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Theme.secondaryBackground)
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

struct CourseRow: View {
    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.primary.opacity(0.1))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "graduationcap.fill")
                        .foregroundColor(Theme.primary)
                )
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Understanding DeFi")
                    .font(.headline)
                
                Text("Learn about decentralized finance and its applications")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    Label("8 Lessons", systemImage: "book.closed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("Start")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(Theme.primary)
                }
            }
        }
        .padding()
        .background(Theme.background)
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

#Preview {
    MainTabView()
} 