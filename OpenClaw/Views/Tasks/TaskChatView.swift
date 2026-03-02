import SwiftUI

struct TaskChatView: View {
    @Environment(AppTheme.self) private var theme
    let agent: Agent
    var initialMessage: String? = nil

    @State private var taskService = TaskService.shared
    @State private var webSocket = WebSocketManager.shared
    @State private var inputText = ""
    @State private var isSending = false
    @State private var hasSentInitial = false

    var body: some View {
        VStack(spacing: 0) {
            chatMessages
            chatInputBar
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                agentHeader
            }
            ToolbarItem(placement: .primaryAction) {
                connectionBadge
            }
        }
        .task {
            try? await taskService.fetchTasks(agentId: agent.id)
            webSocket.connect(agentId: agent.id)

            if let initialMessage, !hasSentInitial {
                hasSentInitial = true
                isSending = true
                try? await Task.sleep(for: .milliseconds(300))
                _ = try? await taskService.submitTask(agentId: agent.id, input: initialMessage)
                isSending = false
            }
        }
        .onDisappear {
            webSocket.disconnect()
        }
    }

    // MARK: - Toolbar Items

    private var agentHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: agent.persona.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    LinearGradient(
                        colors: agentColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(agent.name)
                .font(.subheadline.weight(.semibold))
        }
    }

    private var agentColors: [Color] {
        switch agent.persona {
        case .professional: [.blue, .cyan]
        case .friendly: [.teal, .cyan]
        case .technical: [.purple, .indigo]
        case .creative: [.pink, .orange]
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(webSocket.isConnected ? .green : .red)
                .frame(width: 6, height: 6)
            Text(webSocket.isConnected ? "Live" : "Offline")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(Capsule())
    }

    // MARK: - Chat Messages

    private var chatMessages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(taskService.tasks.reversed()) { task in
                        TaskBubbleView(task: task)
                            .id(task.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: taskService.tasks.count) {
                if let last = taskService.tasks.first {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input Bar

    private var chatInputBar: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.5)

            HStack(alignment: .bottom, spacing: 10) {
                HStack(spacing: 8) {
                    Button {} label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    TextField("Ask your agent...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .font(.subheadline)

                    Button {} label: {
                        Image(systemName: "globe")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 22))

                Button {
                    sendTask()
                } label: {
                    Image(systemName: isSending ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(canSend ? theme.accent : Color(.systemGray4))
                        .symbolEffect(.pulse, isActive: isSending)
                }
                .disabled(!canSend && !isSending)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func sendTask() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        isSending = true

        Task {
            _ = try? await taskService.submitTask(agentId: agent.id, input: text)
            isSending = false
        }
    }
}
