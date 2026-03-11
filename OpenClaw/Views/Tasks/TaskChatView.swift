import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Speech

struct TaskChatView: View {
    @Environment(AppTheme.self) private var theme
    let agent: Agent
    var initialMessage: String? = nil

    @State private var agentService = AgentService.shared
    @State private var taskService = TaskService.shared
    @State private var webSocket = WebSocketManager.shared

    private var liveAgent: Agent {
        agentService.agents.first(where: { $0.id == agent.id }) ?? agent
    }
    @State private var inputText = ""
    @State private var isSending = false
    @State private var hasSentInitial = false
    @State private var showClearConfirmation = false
    @State private var webSearchEnabled = false

    @State private var attachments: [FileAttachment] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showDocumentPicker = false
    @State private var showPhotoPicker = false
    @State private var isUploading = false

    @State private var speechService = SpeechRecognitionService.shared
    @State private var showSpeechPermissionDenied = false
    @State private var configuringSkill: Agent.InstalledSkill?

    private let maxFileSize = 25 * 1024 * 1024

    var body: some View {
        VStack(spacing: 0) {
            chatMessages
            unconfiguredSkillsBanner
            attachmentPreview
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
                        if !unconfiguredSkills.isEmpty {
                            ForEach(unconfiguredSkills) { skill in
                                Button {
                                    configuringSkill = skill
                                } label: {
                                    Label("Configure \(skill.name)", systemImage: "key.fill")
                                }
                            }
                            Divider()
                        }
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
        .onChange(of: selectedPhotoItems) { _, newItems in
            loadPhotos(from: newItems)
        }
        .alert("File Too Large", isPresented: .init(
            get: { fileSizeError != nil },
            set: { if !$0 { fileSizeError = nil } }
        )) {
            Button("OK", role: .cancel) { fileSizeError = nil }
        } message: {
            Text(fileSizeError ?? "")
        }
        .sheet(item: $configuringSkill) { skill in
            SkillCredentialSheet(agentId: agent.id, skill: skill)
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 5,
            matching: .images,
            photoLibrary: .shared()
        )
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker(
                allowedContentTypes: [.item],
                allowsMultipleSelection: true,
                onPick: handlePickedDocuments
            )
        }
        .task {
            async let fetchTasks: () = { try? await taskService.fetchTasks(agentId: agent.id) }()
            async let refreshSkills: () = { try? await agentService.fetchAgents() }()
            _ = await (fetchTasks, refreshSkills)

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

    // MARK: - Attachment Preview

    @ViewBuilder
    private var attachmentPreview: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        attachmentTile(attachment)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(.bar)
        }
    }

    private func attachmentTile(_ attachment: FileAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            if attachment.isImage, let uiImage = UIImage(data: attachment.data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 4) {
                    Image(systemName: attachment.iconName)
                        .font(.system(size: 20))
                        .foregroundStyle(theme.accent)
                    Text(attachment.filename)
                        .font(.system(size: 8, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                    Text(attachment.formattedSize)
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 64, height: 64)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if attachment.isUploading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 64, height: 64)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if attachment.uploadFailed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                    .offset(x: 4, y: -4)
            }

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    attachments.removeAll { $0.id == attachment.id }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .offset(x: 6, y: -6)
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

            if speechService.isListening {
                speechListeningBanner
            }

            HStack(alignment: .bottom, spacing: 10) {
                HStack(spacing: 8) {
                    Menu {
                        Button {
                            showPhotoPicker = true
                        } label: {
                            Label("Photo Library", systemImage: "photo.on.rectangle")
                        }

                        Button {
                            showDocumentPicker = true
                        } label: {
                            Label("Choose File", systemImage: "doc")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(!attachments.isEmpty ? theme.accent : .secondary.opacity(0.5))
                    }
                    .accessibilityIdentifier("chat_attach")

                    TextField("Ask your agent...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .font(.subheadline)
                        .accessibilityIdentifier("chat_input")

                    Button {
                        toggleSpeechRecognition()
                    } label: {
                        Image(systemName: speechService.isListening ? "mic.fill" : "mic")
                            .font(.system(size: 17))
                            .foregroundStyle(speechService.isListening ? .red : .secondary.opacity(0.5))
                            .symbolEffect(.pulse, isActive: speechService.isListening)
                    }
                    .accessibilityIdentifier("chat_mic")

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
                        .stroke(
                            speechService.isListening ? Color.red.opacity(0.4) : Color(.separator).opacity(0.15),
                            lineWidth: speechService.isListening ? 1.5 : 0.5
                        )
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
        .alert("Microphone Access Required", isPresented: $showSpeechPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enable microphone and speech recognition access in Settings to use voice input.")
        }
    }

    private var speechListeningBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .opacity(speechService.isListening ? 1 : 0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: speechService.isListening)

            Text(speechService.transcribedText.isEmpty ? "Listening..." : speechService.transcribedText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(speechService.transcribedText.isEmpty ? .secondary : .primary)
                .lineLimit(2)

            Spacer()

            Button {
                finishSpeechRecognition()
            } label: {
                Text("Done")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.06))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !attachments.isEmpty
        return (hasText || hasAttachments) && !isSending && !isUploading
    }

    // MARK: - Unconfigured Skills

    private var unconfiguredSkills: [Agent.InstalledSkill] {
        liveAgent.skills.filter { skill in
            guard skill.source == "clawhub" else { return false }
            guard let config = skill.config else { return true }
            if case .bool(true) = config["_configured"] { return false }
            if case .string(let keys) = config["_env_keys"], !keys.isEmpty { return true }
            return false
        }
    }

    @ViewBuilder
    private var unconfiguredSkillsBanner: some View {
        if !unconfiguredSkills.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(unconfiguredSkills) { skill in
                        Button {
                            configuringSkill = skill
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                                Text("Set up \(skill.name)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.orange.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(.orange.opacity(0.2), lineWidth: 0.5)
                            )
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .background(.bar)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Speech Recognition

    private func toggleSpeechRecognition() {
        if speechService.isListening {
            finishSpeechRecognition()
            return
        }

        if speechService.needsPermission {
            Task {
                let granted = await speechService.requestPermissions()
                if granted {
                    startSpeechRecognition()
                } else {
                    showSpeechPermissionDenied = true
                }
            }
            return
        }

        guard speechService.isAvailable else {
            showSpeechPermissionDenied = true
            return
        }

        startSpeechRecognition()
    }

    private func startSpeechRecognition() {
        speechService.reset()
        do {
            try speechService.startListening()
        } catch {
            print("Speech recognition error: \(error.localizedDescription)")
        }
    }

    private func finishSpeechRecognition() {
        let text = speechService.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        speechService.stopListening()
        if !text.isEmpty {
            if inputText.isEmpty {
                inputText = text
            } else {
                inputText += " " + text
            }
        }
        speechService.reset()
    }

    // MARK: - Actions

    private func sendTask() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }

        let filesToUpload = attachments
        let input = text.isEmpty ? "[Files attached: \(filesToUpload.map(\.filename).joined(separator: ", "))]" : text

        inputText = ""
        isSending = true
        isUploading = !filesToUpload.isEmpty

        Task {
            var uploadedIds: [String] = []

            for i in filesToUpload.indices {
                let attachment = filesToUpload[i]
                if let idx = attachments.firstIndex(where: { $0.id == attachment.id }) {
                    attachments[idx].isUploading = true
                }

                do {
                    let response = try await APIClient.shared.uploadFile(
                        data: attachment.data,
                        filename: attachment.filename,
                        mimeType: attachment.mimeType
                    )
                    uploadedIds.append(response.fileId)

                    if let idx = attachments.firstIndex(where: { $0.id == attachment.id }) {
                        attachments[idx].uploadedFileId = response.fileId
                        attachments[idx].isUploading = false
                    }
                } catch {
                    if let idx = attachments.firstIndex(where: { $0.id == attachment.id }) {
                        attachments[idx].isUploading = false
                        attachments[idx].uploadFailed = true
                    }
                }
            }

            isUploading = false
            attachments.removeAll()
            selectedPhotoItems.removeAll()

            _ = try? await taskService.submitTask(
                agentId: agent.id,
                input: input,
                webSearch: webSearchEnabled,
                fileIds: uploadedIds.isEmpty ? nil : uploadedIds
            )
            isSending = false
        }
    }

    @State private var fileSizeError: String?

    private func loadPhotos(from items: [PhotosPickerItem]) {
        for item in items {
            let attachmentId = item.itemIdentifier ?? UUID().uuidString
            guard !attachments.contains(where: { $0.id == attachmentId }) else { continue }

            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }

                let jpegData: Data
                if let uiImage = UIImage(data: data),
                   let converted = uiImage.jpegData(compressionQuality: 0.85) {
                    jpegData = converted
                } else {
                    jpegData = data
                }

                if jpegData.count > maxFileSize {
                    fileSizeError = "Image is too large (max 25 MB)"
                    return
                }

                let filename = "photo_\(attachmentId.suffix(6)).jpg"

                let attachment = FileAttachment(
                    id: attachmentId,
                    filename: filename,
                    mimeType: "image/jpeg",
                    data: jpegData
                )
                withAnimation(.easeOut(duration: 0.2)) {
                    attachments.append(attachment)
                }
            }
        }
    }

    private func handlePickedDocuments(_ urls: [URL]) {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let data = try? Data(contentsOf: url) else { continue }

            if data.count > maxFileSize {
                fileSizeError = "\(url.lastPathComponent) is too large (max 25 MB)"
                continue
            }

            let mimeType = FileAttachment.mimeType(for: url)
            let attachment = FileAttachment(
                id: UUID().uuidString,
                filename: url.lastPathComponent,
                mimeType: mimeType,
                data: data
            )
            withAnimation(.easeOut(duration: 0.2)) {
                attachments.append(attachment)
            }
        }
    }
}
