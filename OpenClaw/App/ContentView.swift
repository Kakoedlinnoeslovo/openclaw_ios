import SwiftUI

struct ContentView: View {
    @Environment(AuthService.self) private var auth
    /// Must use AppStorage so toggling funnel completion (e.g. paywall close) triggers a view refresh. Plain UserDefaults reads do not.
    @AppStorage(OnboardingFunnel.completeKey) private var onboardingFunnelComplete = false

    private var showMainApp: Bool {
        auth.isAuthenticated && onboardingFunnelComplete
    }

    var body: some View {
        Group {
            if showMainApp {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
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
    @Environment(\.colorScheme) private var colorScheme
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

    private var dockBackground: Color {
        colorScheme == .dark ? Color(white: 0.11) : Color(.systemGray6)
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabBarItem(icon: "square.grid.2x2.fill", iconInactive: "square.grid.2x2", label: "Home", tag: 0)

            Spacer(minLength: 4)

            Color.clear.frame(width: 64, height: 1)

            Spacer(minLength: 4)

            tabBarItem(icon: "clock.arrow.circlepath", iconInactive: "clock.arrow.circlepath", label: "History", tag: 2)

            Spacer(minLength: 4)

            tabBarItem(icon: "gearshape.fill", iconInactive: "gearshape", label: "Settings", tag: 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background {
            Capsule(style: .continuous)
                .fill(dockBackground)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.42 : 0.12), radius: 20, y: 10)
        }
        .overlay(alignment: .center) {
            centerButton
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
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
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(
                    LinearGradient(
                        colors: theme.heroGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .shadow(color: theme.accent.opacity(0.55), radius: 18, y: 6)
                .shadow(color: theme.accent.opacity(0.35), radius: 8, y: 2)
        }
        .offset(y: -12)
        .accessibilityIdentifier("tab_plus")
    }
}
