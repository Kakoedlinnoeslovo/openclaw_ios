import SwiftUI

struct ContentView: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppTheme.self) private var theme
    @State private var showTrialPaywall = false

    var body: some View {
        Group {
            if auth.isAuthenticated {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut, value: auth.isAuthenticated)
        .onChange(of: auth.isAuthenticated) { _, isAuth in
            if isAuth && !theme.hasSeenTrialPaywall {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showTrialPaywall = true
                }
            }
        }
        .sheet(isPresented: $showTrialPaywall) {
            theme.hasSeenTrialPaywall = true
        } content: {
            PaywallView()
        }
    }

    static func openAppStoreReview() {
        guard let url = URL(string: "itms-apps://itunes.apple.com/app/id\(AppConstants.appStoreID)?action=write-review") else { return }
        UIApplication.shared.open(url)
    }
}

struct MainTabView: View {
    @Environment(AppTheme.self) private var theme
    @Environment(AuthService.self) private var auth
    @State private var selectedTab = 0
    @State private var showQuickChat = false
    @State private var createdAgent: Agent?
    @State private var agentService = AgentService.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tag(0)

                Color.clear
                    .tag(1)

                HistoryView()
                    .tag(2)

                SettingsView()
                    .tag(3)
            }
            .toolbar(.hidden, for: .tabBar)

            customTabBar
        }
        .fullScreenCover(isPresented: $showQuickChat) {
            NavigationStack {
                if let agent = agentService.preferredAgent {
                    TaskChatView(agent: agent)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showQuickChat = false }
                            }
                        }
                } else {
                    AgentCreationView(onCreated: { agent in
                        showQuickChat = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            createdAgent = agent
                        }
                    })
                }
            }
        }
        .fullScreenCover(item: $createdAgent) { agent in
            NavigationStack {
                TaskChatView(agent: agent)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { createdAgent = nil }
                        }
                    }
            }
        }
        .task {
            try? await agentService.fetchAgents()
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabBarItem(icon: "square.grid.2x2.fill", iconInactive: "square.grid.2x2", label: "Home", tag: 0)

            Spacer()

            centerButton

            Spacer()

            tabBarItem(icon: "clock.arrow.circlepath", iconInactive: "clock.arrow.circlepath", label: "History", tag: 2)

            Spacer()

            tabBarItem(icon: "gearshape.fill", iconInactive: "gearshape", label: "Settings", tag: 3)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: .black.opacity(0.06), radius: 16, y: -6)
        )
    }

    private func tabBarItem(icon: String, iconInactive: String, label: String, tag: Int) -> some View {
        let isSelected = selectedTab == tag
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tag }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? icon : iconInactive)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? theme.accent : .secondary.opacity(0.7))
                    .scaleEffect(isSelected ? 1.05 : 1.0)

                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? theme.accent : .secondary.opacity(0.7))
            }
            .frame(width: 64)
        }
        .accessibilityIdentifier("tab_\(label.lowercased())")
    }

    private var centerButton: some View {
        Button {
            showQuickChat = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(
                        colors: theme.heroGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .shadow(color: theme.accent.opacity(0.35), radius: 12, y: 4)
        }
        .offset(y: -8)
        .accessibilityIdentifier("tab_plus")
    }
}
