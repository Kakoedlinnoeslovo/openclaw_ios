import SwiftUI
import PhotosUI

struct TaskChatView: View {
    @Environment(AppTheme.self) private var theme
    let agent: Agent
    var initialMessage: String? = nil

    @State private var taskService = TaskService.shared
    @State private var webSocket = WebSocketManager.shared
    @State private var inputText = ""
    @State private var isSending = false
    @State private var hasSentInitial = false
    @State private var showClearConfirmation = false
    @State private var webSearchEnabled = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var showAttachmentMenu = false

    var body: some View {
        VStack(spacing: 0) {
            chatMessages
            imagePreview
            chatInputBar
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                agentHeader
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    connectionBadge
                    Menu {
                        Button(role: .destructive) {
                            showClearConfirmation = true
                        } label: {
                            Label("Clear History", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("chat_menu")
                }
            }
        }
        .confirmationDialog("Clear conversation history?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) {
                Task { _ = try? await taskService.clearHistory(agentId: agent.id) }
            }
        } message: {
            Text("This will permanently delete all completed tasks for this agent.")
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            loadImage(from: newItem)
        }
        .task {
            try? await taskService.fetchTasks(agentId: agent.id)
            webSocket.connect(agentId: agent.id)

            if let initialMessage, !hasSentInitial {
                hasSentInitial = true
                isSending = true
                try? await Task.sleep(for: .milliseconds(300))
                _ = try? await taskService.submitTask(
                    agentId: agent.id,
                    input: initialMessage,
                    imageData: nil,
                    webSearch: false
                )
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
                .frame(width: 30, height: 30)
                .background(
                    LinearGradient(
                        colors: agentColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .shadow(color: agentColors.first?.opacity(0.2) ?? .clear, radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(agent.name)
                    .font(.system(size: 15, weight: .semibold))
                Text(agent.model.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var agentColors: [Color] {
        switch agent.persona {
        case .professional: [Color(red: 0.30, green: 0.45, blue: 1.0), Color(red: 0.20, green: 0.70, blue: 0.90)]
        case .friendly: [Color(red: 0.20, green: 0.75, blue: 0.65), Color(red: 0.30, green: 0.85, blue: 0.80)]
        case .technical: [Color(red: 0.55, green: 0.30, blue: 0.90), Color(red: 0.40, green: 0.25, blue: 0.80)]
        case .creative: [Color(red: 0.90, green: 0.40, blue: 0.55), Color(red: 0.95, green: 0.55, blue: 0.35)]
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(webSocket.isConnected ? Color.green : Color.red.opacity(0.8))
                .frame(width: 5, height: 5)
            Text(webSocket.isConnected ? "Live" : "Offline")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
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

    // MARK: - Image Preview

    @ViewBuilder
    private var imagePreview: some View {
        if let imageData = selectedImageData, let uiImage = UIImage(data: imageData) {
            HStack {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button {
                        selectedImageData = nil
                        selectedPhotoItem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .offset(x: 6, y: -6)
                    .accessibilityIdentifier("chat_remove_image")
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
    }

    // MARK: - Input Bar

    private var chatInputBar: some View {
        VStack(spacing: 0) {
            if webSearchEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                    Text("Web search enabled")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(theme.accent)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(theme.accent.opacity(0.06))
            }

            HStack(alignment: .bottom, spacing: 10) {
                HStack(spacing: 8) {
                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(selectedImageData != nil ? theme.accent : .secondary.opacity(0.5))
                    }
                    .accessibilityIdentifier("chat_attach")

                    TextField("Ask your agent...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .font(.subheadline)
                        .accessibilityIdentifier("chat_input")

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            webSearchEnabled.toggle()
                        }
                    } label: {
                        Image(systemName: webSearchEnabled ? "globe.americas.fill" : "globe")
                            .font(.system(size: 17))
                            .foregroundStyle(webSearchEnabled ? theme.accent : .secondary.opacity(0.5))
                    }
                    .accessibilityIdentifier("chat_web_toggle")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color(.separator).opacity(0.15), lineWidth: 0.5)
                )

                Button {
                    sendTask()
                } label: {
                    Image(systemName: isSending ? "stop.fill" : "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            canSend || isSending
                                ? AnyShapeStyle(LinearGradient(colors: theme.accentGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(Color(.systemGray4))
                        )
                        .clipShape(Circle())
                        .shadow(color: canSend ? theme.accent.opacity(0.3) : .clear, radius: 6, y: 2)
                        .symbolEffect(.pulse, isActive: isSending)
                }
                .disabled(!canSend && !isSending)
                .accessibilityIdentifier("chat_send")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = selectedImageData != nil
        return (hasText || hasImage) && !isSending
    }

    private func sendTask() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || selectedImageData != nil else { return }

        let input = text.isEmpty ? "[Image attached]" : text
        let imageToSend = selectedImageData

        inputText = ""
        selectedImageData = nil
        selectedPhotoItem = nil
        isSending = true

        Task {
            _ = try? await taskService.submitTask(
                agentId: agent.id,
                input: input,
                imageData: imageToSend,
                webSearch: webSearchEnabled
            )
            isSending = false
        }
    }

    private func loadImage(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                selectedImageData = data
            }
        }
    }
}
