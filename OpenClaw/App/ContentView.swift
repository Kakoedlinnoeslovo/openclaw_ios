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
        Group {
            switch selectedTab {
            case 0:
                HomeView()
            case 2:
                HistoryView()
            default:
                HomeView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            customTabBar
        }
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
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

    private var dockTint: Color {
        colorScheme == .dark ? Color(white: 0.11) : Color(.systemGray6)
    }

    @ViewBuilder
    private var dockChrome: some View {
        let cap = Capsule(style: .continuous)
        ZStack {
            cap.fill(dockTint)
            if #available(iOS 26.0, *) {
                cap
                    .fill(Color.clear)
                    .glassEffect(.regular, in: cap)
            } else {
                cap.fill(.ultraThinMaterial)
            }
            cap.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabBarItem(icon: "square.grid.2x2.fill", iconInactive: "square.grid.2x2", label: "Home", tag: 0)

            Spacer(minLength: 4)

            Color.clear.frame(width: 64, height: 1)

            Spacer(minLength: 4)

            tabBarItem(icon: "clock.arrow.circlepath", iconInactive: "clock.arrow.circlepath", label: "History", tag: 2)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background {
            dockChrome
        }
        .overlay(alignment: .center) {
            centerButton
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 4)
    }

    private func tabBarItem(icon: String, iconInactive: String, label: String, tag: Int) -> some View {
        let isSelected = selectedTab == tag
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tag }
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [
                                    theme.accent.opacity(colorScheme == .dark ? 0.5 : 0.38),
                                    theme.accent.opacity(colorScheme == .dark ? 0.18 : 0.14),
                                    theme.accent.opacity(0.03),
                                    Color.clear,
                                ],
                                center: UnitPoint(x: 0.5, y: 0.36),
                                startRadius: 2,
                                endRadius: 52,
                            )
                        )
                        .frame(width: 70, height: 58)
                        .allowsHitTesting(false)

                    Circle()
                        .fill(theme.accent.opacity(colorScheme == .dark ? 0.45 : 0.35))
                        .frame(width: 32, height: 32)
                        .blur(radius: 20)
                        .offset(y: -10)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }

                VStack(spacing: 3) {
                    Image(systemName: isSelected ? icon : iconInactive)
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? theme.accent : .secondary.opacity(0.7))
                        .scaleEffect(isSelected ? 1.08 : 1.0)
                        .shadow(color: isSelected ? theme.accent.opacity(0.55) : .clear, radius: 12, y: 0)

                    Text(label)
                        .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? theme.accent : .secondary.opacity(0.7))
                }
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
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
                .shadow(color: theme.accent.opacity(0.4), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .offset(y: -5)
        .accessibilityIdentifier("tab_plus")
    }
}
