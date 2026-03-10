import SwiftUI

struct HistoryView: View {
    @Environment(AppTheme.self) private var theme
    @State private var agentService = AgentService.shared
    @State private var taskService = TaskService.shared
    @State private var historyItems: [HistoryItem] = []
    @State private var isLoading = false
    @State private var selectedItem: HistoryItem?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && historyItems.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if historyItems.isEmpty {
                    emptyState
                } else {
                    historyList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("History")
            .fullScreenCover(item: $selectedItem) { item in
                if let agent = agentService.agents.first(where: { $0.id == item.agentId }) {
                    NavigationStack {
                        TaskChatView(agent: agent)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Close") { selectedItem = nil }
                                }
                            }
                    }
                }
            }
            .refreshable { await loadHistory() }
            .task { await loadHistory() }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            floatingIconsCluster

            VStack(spacing: 8) {
                Text("History is Empty")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Text("The history of your requests will be\nstored here")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
            Spacer()
        }
        .accessibilityIdentifier("history_empty")
    }

    private var floatingIconsCluster: some View {
        let icons: [(String, Double, CGFloat)] = [
            ("envelope.fill", -50, -80),
            ("briefcase.fill", 0, -110),
            ("text.justify.left", 55, -80),
            ("link", -80, -10),
            ("clock.arrow.circlepath", 0, -20),
            ("text.bubble.fill", 80, -10),
            ("textformat.size", -50, 55),
            ("atom", 55, 55),
            ("function", 0, 85),
        ]

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [theme.accent.opacity(0.10), theme.accent.opacity(0.03), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 140
                    )
                )
                .frame(width: 280, height: 280)

            Circle()
                .stroke(theme.accent.opacity(0.06), lineWidth: 1)
                .frame(width: 180, height: 180)

            ForEach(Array(icons.enumerated()), id: \.offset) { _, item in
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 46, height: 46)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )

                    Image(systemName: item.0)
                        .font(.system(size: 16))
                        .foregroundStyle(theme.accent.opacity(0.55))
                }
                .offset(x: item.1, y: item.2)
            }
        }
        .frame(height: 240)
    }

    // MARK: - History List

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(historyItems) { item in
                    Button {
                        selectedItem = item
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            colors: theme.accentGradient,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 42, height: 42)

                                Image(systemName: "cpu")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.agentName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text(item.lastMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text(item.timeAgo)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)

                                Text("\(item.taskCount)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(.tertiarySystemGroupedBackground))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .accessibilityIdentifier("history_item_\(item.id)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Data

    private func loadHistory() async {
        isLoading = true
        defer { isLoading = false }

        var items: [HistoryItem] = []
        for agent in agentService.agents {
            if let tasks = try? await fetchAgentTasks(agentId: agent.id), !tasks.isEmpty {
                let sorted = tasks.sorted { ($0.createdAt) > ($1.createdAt) }
                let last = sorted.first
                items.append(HistoryItem(
                    id: agent.id,
                    agentId: agent.id,
                    agentName: agent.name,
                    lastMessage: last?.input ?? "",
                    timestamp: last?.createdAt ?? Date(),
                    taskCount: tasks.count
                ))
            }
        }
        historyItems = items.sorted { $0.timestamp > $1.timestamp }
    }

    private func fetchAgentTasks(agentId: String) async throws -> [TaskItem] {
        struct TasksResponse: Codable { let tasks: [TaskItem] }
        let response: TasksResponse = try await APIClient.shared.get("/agents/\(agentId)/tasks")
        return response.tasks
    }
}

// MARK: - History Item Model

struct HistoryItem: Identifiable {
    let id: String
    let agentId: String
    let agentName: String
    let lastMessage: String
    let timestamp: Date
    let taskCount: Int

    var timeAgo: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
