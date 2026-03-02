import SwiftUI
import WebKit

struct ClawHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTheme.self) private var theme

    var initialPath: String?

    @State private var currentURL: URL?
    @State private var agentService = AgentService.shared
    @State private var taskService = TaskService.shared
    @State private var webSocket = WebSocketManager.shared

    @State private var showAgentPicker = false
    @State private var installState: InstallState = .idle
    @State private var pendingSlug: String?
    @State private var activeTaskId: String?
    @State private var installOutput: String?

    private var startURL: URL {
        if let path = initialPath {
            return URL(string: "https://clawhub.ai/\(path)")!
        }
        return URL(string: "https://clawhub.ai/skills?nonSuspicious=true")!
    }

    private var detectedSkillSlug: String? {
        guard let url = currentURL,
              url.host()?.contains("clawhub") == true else { return nil }

        let path = url.path()
        let segments = path.split(separator: "/").map(String.init)

        // Skill pages: /user/skill-name or /skills/skill-name
        if segments.count == 2 {
            let first = segments[0]
            if first != "skills" || segments[1].count > 2 {
                return segments.joined(separator: "/")
            }
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ClawHubWebView(url: startURL, currentURL: $currentURL)
                    .ignoresSafeArea(edges: .bottom)

                if let slug = detectedSkillSlug {
                    installBar(slug: slug)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if installState == .installing || installState == .success || installState == .failed {
                    installProgressOverlay
                        .transition(.opacity)
                }
            }
            .animation(.spring(duration: 0.3), value: detectedSkillSlug)
            .animation(.spring(duration: 0.3), value: installState)
            .navigationTitle("ClawHub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAgentPicker) {
                agentPickerSheet
            }
            .task {
                try? await agentService.fetchAgents()
            }
            .onChange(of: taskService.tasks) {
                guard let taskId = activeTaskId,
                      let task = taskService.tasks.first(where: { $0.id == taskId }) else { return }
                installOutput = task.output
                switch task.status {
                case .completed:
                    installState = .success
                case .failed:
                    installState = .failed
                case .running:
                    installState = .installing
                case .queued:
                    break
                }
            }
        }
    }

    // MARK: - Install Bar

    private func installBar(slug: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        LinearGradient(
                            colors: [.orange, .red.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(skillDisplayName(from: slug))
                        .font(.subheadline.weight(.semibold))
                    Text(slug)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    pendingSlug = slug
                    if agentService.agents.count == 1 {
                        installSkill(slug: slug, agentId: agentService.agents[0].id)
                    } else {
                        showAgentPicker = true
                    }
                } label: {
                    Text("Install")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(theme.accent)
                        .clipShape(Capsule())
                }
                .disabled(installState == .installing)
            }
            .padding(16)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.1), radius: 12, y: -4)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Install Progress Overlay

    private var installProgressOverlay: some View {
        VStack {
            Spacer()

            VStack(spacing: 20) {
                Group {
                    switch installState {
                    case .installing:
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Installing skill...")
                                .font(.headline)
                            if let slug = pendingSlug {
                                Text(slug)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    case .success:
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.green)
                            Text("Skill installed!")
                                .font(.headline)
                            if let output = installOutput, !output.isEmpty {
                                Text(output)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(4)
                            }
                        }
                    case .failed:
                        VStack(spacing: 12) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.red)
                            Text("Installation failed")
                                .font(.headline)
                            if let output = installOutput, !output.isEmpty {
                                Text(output)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(4)
                            }
                        }
                    default:
                        EmptyView()
                    }
                }

                if installState == .success || installState == .failed {
                    Button {
                        withAnimation {
                            installState = .idle
                            activeTaskId = nil
                            installOutput = nil
                        }
                    } label: {
                        Text(installState == .success ? "Done" : "Dismiss")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(installState == .success ? Color.green : theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.15), radius: 20, y: -5)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color.black.opacity(0.3).ignoresSafeArea())
    }

    // MARK: - Agent Picker

    private var agentPickerSheet: some View {
        NavigationStack {
            List(agentService.agents) { agent in
                Button {
                    showAgentPicker = false
                    if let slug = pendingSlug {
                        installSkill(slug: slug, agentId: agent.id)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: agent.persona.icon)
                            .font(.title3)
                            .foregroundStyle(theme.accent)
                            .frame(width: 36, height: 36)
                            .background(theme.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(agent.model.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .navigationTitle("Install to Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAgentPicker = false }
                }
            }
            .overlay {
                if agentService.agents.isEmpty {
                    ContentUnavailableView(
                        "No Agents",
                        systemImage: "cpu",
                        description: Text("Create an agent first to install skills.")
                    )
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Install Logic

    private func installSkill(slug: String, agentId: String) {
        installState = .installing
        activeTaskId = nil
        installOutput = nil

        webSocket.connect(agentId: agentId)

        Task {
            let prompt = "Install the ClawHub skill \"\(slug)\" by running: clawhub install \(slug)"
            let response = try? await taskService.submitTask(agentId: agentId, input: prompt)
            activeTaskId = response?.taskId
        }
    }

    private func skillDisplayName(from slug: String) -> String {
        let name = slug.split(separator: "/").last.map(String.init) ?? slug
        return name.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

// MARK: - Install State

private enum InstallState: Equatable {
    case idle
    case installing
    case success
    case failed
}

// MARK: - WebView

struct ClawHubWebView: UIViewRepresentable {
    let url: URL
    @Binding var currentURL: URL?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: ClawHubWebView
        init(_ parent: ClawHubWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.currentURL = webView.url
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if let url = navigationAction.request.url {
                Task { @MainActor in
                    parent.currentURL = url
                }
            }
            return .allow
        }
    }
}
