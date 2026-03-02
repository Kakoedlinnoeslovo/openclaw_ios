import SwiftUI

struct HomeView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SubscriptionService.self) private var subscription
    @Environment(AppTheme.self) private var theme
    @State private var agentService = AgentService.shared
    @State private var showCreateAgent = false
    @State private var selectedAgent: Agent?
    @State private var showPaywall = false
    @State private var quickChatState: QuickChatState?
    @State private var activeQuickAction: QuickAction?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    greetingHeader
                    quickActionGrid
                    agentsSection
                }
                .padding(.bottom, 100)
            }
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .bottom) { floatingButton }
            .sheet(isPresented: $showCreateAgent) {
                AgentCreationView()
            }
            .navigationDestination(item: $selectedAgent) { agent in
                AgentDetailView(agent: agent)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .fullScreenCover(item: $quickChatState) { state in
                NavigationStack {
                    TaskChatView(agent: state.agent, initialMessage: state.initialMessage)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { quickChatState = nil }
                            }
                        }
                }
            }
            .sheet(item: $activeQuickAction) { action in
                NavigationStack {
                    QuickActionInputView(action: action) { message in
                        activeQuickAction = nil
                        if let agent = agentService.agents.first {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                quickChatState = QuickChatState(agent: agent, initialMessage: message)
                            }
                        }
                    }
                    .navigationTitle(action.rawValue)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { activeQuickAction = nil }
                        }
                    }
                }
                .presentationDetents([.large])
            }
            .refreshable {
                try? await agentService.fetchAgents()
            }
            .task {
                try? await agentService.fetchAgents()
            }
        }
    }

    // MARK: - Greeting Header

    private var greetingHeader: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greetingText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("What can I help you with?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                avatarButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if subscription.currentTier == .free {
                proBanner
            }
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let name = auth.currentUser?.displayName.components(separatedBy: " ").first ?? ""
        let prefix = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Hey there"
        }
        return name.isEmpty ? "\(prefix)!" : "\(prefix), \(name)!"
    }

    private var avatarButton: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: theme.accentGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)

            Text(avatarInitial)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var avatarInitial: String {
        String(auth.currentUser?.displayName.prefix(1) ?? "O")
    }

    private var proBanner: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Unlock Everything AI")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("GPT-4o, Claude, unlimited agents & more")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.1, green: 0.1, blue: 0.18), Color(red: 0.12, green: 0.12, blue: 0.22)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Quick Action Grid

    private var quickActionGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                spacing: 12
            ) {
                ForEach(QuickAction.allCases) { action in
                    QuickActionChip(
                        icon: action.icon,
                        label: action.rawValue,
                        color: action.color(accent: theme.accent)
                    ) {
                        handleQuickAction(action)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func handleQuickAction(_ action: QuickAction) {
        switch action {
        case .create:
            showCreateAgent = true
        case .chat:
            if let agent = agentService.agents.first {
                quickChatState = QuickChatState(agent: agent, initialMessage: nil)
            } else {
                showCreateAgent = true
            }
        default:
            if agentService.agents.isEmpty {
                showCreateAgent = true
            } else {
                activeQuickAction = action
            }
        }
    }

    // MARK: - Agents Section

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your Agents")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if !agentService.agents.isEmpty {
                    Button {
                        showCreateAgent = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .padding(.horizontal, 20)

            if agentService.isLoading && agentService.agents.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 40)
                    Spacer()
                }
            } else if agentService.agents.isEmpty {
                emptyAgentCard
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(agentService.agents) { agent in
                        AgentCardView(agent: agent)
                            .onTapGesture { selectedAgent = agent }
                    }
                }
                .padding(.horizontal, 20)
            }

            modelsBadge
                .padding(.horizontal, 20)
                .padding(.top, 4)
        }
    }

    private var emptyAgentCard: some View {
        Button { showCreateAgent = true } label: {
            VStack(spacing: 14) {
                Image(systemName: "cpu")
                    .font(.system(size: 36))
                    .foregroundStyle(theme.accent.opacity(0.6))

                Text("Create your first agent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Build a custom AI assistant with skills")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                    .foregroundStyle(theme.accent.opacity(0.3))
            )
        }
        .padding(.horizontal, 20)
    }

    private var modelsBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10))
                .foregroundStyle(theme.accent)
            Text("Built on GPT-4o, Claude Sonnet, and more")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Floating Button

    private var floatingButton: some View {
        Button { showCreateAgent = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    LinearGradient(
                        colors: theme.accentGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .shadow(color: theme.accent.opacity(0.3), radius: 12, y: 6)
        }
        .padding(.bottom, 16)
    }
}

// MARK: - Quick Chat State

struct QuickChatState: Identifiable {
    let id = UUID()
    let agent: Agent
    let initialMessage: String?
}

// MARK: - Quick Action Chip

private struct QuickActionChip: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                    .frame(width: 48, height: 48)
                    .background(color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

extension Agent: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: Agent, rhs: Agent) -> Bool {
        lhs.id == rhs.id
    }
}
