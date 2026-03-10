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
    @State private var showSettings = false

    private let topActions: [QuickAction] = [.chat, .write, .research, .vision]
    private let featuredTools: [QuickAction] = [.web, .email, .voice]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection
                    quickActionCards
                    featuredToolsList
                    agentsSection
                }
                .padding(.bottom, 100)
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showCreateAgent) {
                AgentCreationView(onCreated: { agent in
                    quickChatState = QuickChatState(agent: agent, initialMessage: nil)
                })
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
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
            .refreshable {
                try? await agentService.fetchAgents()
            }
            .task {
                try? await agentService.fetchAgents()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack {
                if subscription.currentTier != .free {
                    HStack(spacing: 4) {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 10))
                        Text("PRO")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.8, blue: 0.3), Color(red: 1.0, green: 0.65, blue: 0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.yellow.opacity(0.10))
                    .clipShape(Capsule())
                }

                Text("OpenClaw")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Spacer()

                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(Circle())
                }
                .accessibilityIdentifier("home_settings")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Button {
                handleQuickAction(.chat)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.accent)

                    Text("Have a question? Ask AI!")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Image(systemName: "mic.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(theme.accent.opacity(0.12), lineWidth: 1)
                )
            }
            .padding(.horizontal, 20)
            .accessibilityIdentifier("home_search_bar")

            if subscription.currentTier == .free {
                proBanner
            }
        }
    }

    private var proBanner: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.8, blue: 0.3), Color(red: 1.0, green: 0.55, blue: 0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)

                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock Everything AI")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("GPT-4o, Claude, unlimited agents & more")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("PRO")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            colors: theme.accentGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [Color.yellow.opacity(0.3), Color.orange.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .padding(.horizontal, 20)
        .accessibilityIdentifier("home_pro_banner")
    }

    // MARK: - Quick Action Cards (2-column)

    private var quickActionCards: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(topActions) { action in
                QuickActionCard(action: action, accentColor: theme.accent) {
                    handleQuickAction(action)
                }
                .accessibilityIdentifier("quick_action_\(action.rawValue.lowercased())")
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Featured Tools List

    private var featuredToolsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Featured Tools")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(Array(featuredTools.enumerated()), id: \.element.id) { index, action in
                    Button {
                        handleQuickAction(action)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: action.icon)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(
                                    LinearGradient(
                                        colors: [action.color(accent: theme.accent), action.color(accent: theme.accent).opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 11))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.headerTitle)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(action.headerSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.quaternary)
                        }
                        .padding(14)
                    }

                    if index < featuredTools.count - 1 {
                        Divider().padding(.leading, 68)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Agents Section

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your Agents")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                if !agentService.agents.isEmpty {
                    Button {
                        showCreateAgent = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(
                                LinearGradient(colors: theme.accentGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .clipShape(Circle())
                    }
                    .accessibilityIdentifier("home_add_agent")
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
                            .accessibilityIdentifier("agent_card_\(agent.id)")
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var emptyAgentCard: some View {
        Button { showCreateAgent = true } label: {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(theme.accent.opacity(0.08))
                        .frame(width: 64, height: 64)

                    Image(systemName: "cpu")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            LinearGradient(colors: theme.accentGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }

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
                    .strokeBorder(theme.accent.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [8, 5]))
            )
        }
        .padding(.horizontal, 20)
        .accessibilityIdentifier("home_empty_agent")
    }

    // MARK: - Actions

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
}

// MARK: - Quick Chat State

struct QuickChatState: Identifiable {
    let id = UUID()
    let agent: Agent
    let initialMessage: String?
}

// MARK: - Quick Action Card (2-column)

private struct QuickActionCard: View {
    let action: QuickAction
    let accentColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: action.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        LinearGradient(
                            colors: [action.color(accent: accentColor), action.color(accent: accentColor).opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: action.color(accent: accentColor).opacity(0.2), radius: 6, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text(action.headerTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(action.headerSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
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
