import SwiftUI

struct AgentDetailView: View {
    @Environment(AppTheme.self) private var theme
    @State var agent: Agent

    @State private var showSkillBrowser = false
    @State private var showChat = false
    @State private var agentService = AgentService.shared
    @State private var configuringSkill: Agent.InstalledSkill?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                agentHeader

                actionButtons

                installedSkillsSection

                recentTasksSection
            }
            .padding()
        }
        .navigationTitle(agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSkillBrowser, onDismiss: syncAgent) {
            NavigationStack {
                SkillBrowserView(agentId: agent.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showSkillBrowser = false }
                        }
                    }
            }
        }
        .onAppear {
            agentService.lastActiveAgentId = agent.id
            syncAgent()
        }
        .sheet(item: $configuringSkill, onDismiss: syncAgent) { skill in
            SkillCredentialSheet(agentId: agent.id, skill: skill)
        }
        .fullScreenCover(isPresented: $showChat, onDismiss: syncAgent) {
            NavigationStack {
                TaskChatView(agent: agent)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showChat = false }
                        }
                    }
            }
        }
    }

    private var agentHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: agent.persona.icon)
                .font(.system(size: 44))
                .foregroundStyle(theme.accent)
                .frame(width: 88, height: 88)
                .background(theme.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 22))

            VStack(spacing: 4) {
                Text(agent.persona.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(agent.model.displayName)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(agent.isActive ? theme.accent : .orange)
                    .frame(width: 8, height: 8)
                Text(agent.isActive ? "Active" : "Inactive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                showChat = true
            } label: {
                Label("Run Task", systemImage: "bolt.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)

            Button {
                showSkillBrowser = true
            } label: {
                Label("Add Skill", systemImage: "puzzlepiece.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
        }
    }

    private var installedSkillsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Installed Skills")
                    .font(.headline)
                Spacer()
                Text("\(agent.skills.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }

            if agent.skills.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "puzzlepiece")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("No skills installed")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(agent.skills) { skill in
                    installedSkillRow(skill)
                }
            }
        }
    }

    private func syncAgent() {
        if let updated = agentService.agents.first(where: { $0.id == agent.id }) {
            agent = updated
        }
    }

    private func skillNeedsKeys(_ skill: Agent.InstalledSkill) -> Bool {
        guard let config = skill.config,
              case .string(let keys) = config["_env_keys"], !keys.isEmpty else { return false }
        return true
    }

    private func skillIsConfigured(_ skill: Agent.InstalledSkill) -> Bool {
        guard let config = skill.config,
              case .bool(true) = config["_configured"] else { return false }
        return true
    }

    private func installedSkillRow(_ skill: Agent.InstalledSkill) -> some View {
        HStack(spacing: 12) {
            Image(systemName: skill.icon)
                .font(.body)
                .foregroundStyle(skill.isEnabled ? theme.accent : .secondary)
                .frame(width: 36, height: 36)
                .background((skill.isEnabled ? theme.accent : Color.secondary).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(skill.isEnabled ? .primary : .secondary)

                    if skill.source == "clawhub" {
                        Text("ClawHub")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.orange)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    Text("v\(skill.version)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if skillNeedsKeys(skill) {
                        if skillIsConfigured(skill) {
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.green)
                        } else {
                            Label("Needs setup", systemImage: "key.fill")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            Spacer()

            Button {
                configuringSkill = skill
            } label: {
                Image(systemName: skillNeedsKeys(skill) && !skillIsConfigured(skill)
                      ? "key.fill" : "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(skillNeedsKeys(skill) && !skillIsConfigured(skill) ? .orange : .secondary)
                    .frame(width: 32, height: 32)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Toggle("", isOn: Binding(
                get: { skill.isEnabled },
                set: { newValue in
                    Task {
                        if let updated = try? await agentService.setSkillEnabled(
                            agentId: agent.id,
                            skillId: skill.skillId,
                            enabled: newValue
                        ) {
                            agent = updated
                        }
                    }
                }
            ))
            .labelsHidden()
            .scaleEffect(0.8)
        }
        .padding(12)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button {
                configuringSkill = skill
            } label: {
                Label("Configure", systemImage: "gearshape.fill")
            }
            Button(role: .destructive) {
                Task {
                    try? await agentService.removeSkill(agentId: agent.id, skillId: skill.skillId)
                    if let idx = agent.skills.firstIndex(where: { $0.id == skill.id }) {
                        agent.skills.remove(at: idx)
                    }
                }
            } label: {
                Label("Uninstall", systemImage: "trash")
            }
        }
    }

    private var recentTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Tasks")
                .font(.headline)

            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Run your first task")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 24)
                Spacer()
            }
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Skill Credential Sheet

struct SkillCredentialSheet: View {
    @Environment(\.dismiss) private var dismiss
    let agentId: String
    let skill: Agent.InstalledSkill

    @State private var agentService = AgentService.shared
    @State private var credentialInputs: [String: String] = [:]
    @State private var isSaving = false
    @State private var saved = false
    @State private var errorMessage: String?
    @State private var requirements: [SkillSetupRequirement] = []
    @State private var installCommands: [String] = []
    @State private var isLoadingRequirements = false
    @State private var isInstallingDeps = false
    @State private var depsInstalled = false
    @State private var setupTaskId: String?

    private var envKeys: [String] {
        if let raw = skill.config?["_env_keys"],
           case .string(let csv) = raw, !csv.isEmpty {
            return csv.components(separatedBy: ",")
        }
        return []
    }

    private var isConfigured: Bool {
        if let flag = skill.config?["_configured"], case .bool(true) = flag {
            return true
        }
        return false
    }

    private var envRequirements: [SkillSetupRequirement] {
        requirements.filter { $0.type == "env" }
    }

    private var binRequirements: [SkillSetupRequirement] {
        requirements.filter { $0.type == "bin" }
    }

    private var allEnvKeys: [String] {
        let fromConfig = envKeys
        let fromRequirements = envRequirements.map(\.key)
        return Array(Set(fromConfig + fromRequirements)).sorted()
    }

    private var hasSetup: Bool {
        !allEnvKeys.isEmpty || !binRequirements.isEmpty || !installCommands.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: skill.icon)
                            .font(.title3)
                            .foregroundStyle(.orange)
                            .frame(width: 40, height: 40)
                            .background(.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(skill.name)
                                .font(.subheadline.weight(.semibold))
                            HStack(spacing: 6) {
                                Text("v\(skill.version)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if skill.source != nil {
                                    Text(skill.source == "clawhub" ? "ClawHub" : "Curated")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(skill.source == "clawhub" ? .orange : .blue)
                                        .clipShape(Capsule())
                                }
                                if isConfigured && !saved {
                                    Label("Configured", systemImage: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }

                if isLoadingRequirements {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Checking requirements…")
                                .font(.subheadline)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                } else if !hasSetup {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                                Text("No configuration needed")
                                    .font(.subheadline.weight(.medium))
                                Text("This skill works out of the box.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 12)
                            Spacer()
                        }
                    }
                } else {
                    if !allEnvKeys.isEmpty {
                        Section("Credentials") {
                            ForEach(allEnvKeys, id: \.self) { key in
                                let isSensitive = key.contains("KEY") || key.contains("TOKEN") || key.contains("SECRET")
                                let label = key.replacingOccurrences(of: "_", with: " ")
                                    .lowercased()
                                    .split(separator: " ")
                                    .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                                    .joined(separator: " ")

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(label)
                                        .font(.caption.weight(.medium))
                                    if isSensitive {
                                        SecureField(key, text: fieldBinding(for: key))
                                            .font(.subheadline.monospaced())
                                            .autocorrectionDisabled()
                                            .textInputAutocapitalization(.never)
                                            .disabled(saved)
                                    } else {
                                        TextField(key, text: fieldBinding(for: key))
                                            .font(.subheadline.monospaced())
                                            .autocorrectionDisabled()
                                            .textInputAutocapitalization(.never)
                                            .disabled(saved)
                                    }
                                    Text(key)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        Section {
                            Button {
                                saveCredentials()
                            } label: {
                                HStack {
                                    Spacer()
                                    if isSaving {
                                        ProgressView()
                                    } else if saved {
                                        Label("Saved", systemImage: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    } else {
                                        Label(isConfigured ? "Update Credentials" : "Save & Configure",
                                              systemImage: "checkmark.shield.fill")
                                    }
                                    Spacer()
                                }
                                .font(.headline)
                            }
                            .disabled(isSaving || saved || !hasAnyInput)
                        }
                    }

                    if !binRequirements.isEmpty || !installCommands.isEmpty {
                        Section("Dependencies") {
                            ForEach(binRequirements) { req in
                                HStack(spacing: 10) {
                                    Image(systemName: "terminal.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .frame(width: 28, height: 28)
                                        .background(.orange.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(req.label)
                                            .font(.subheadline.weight(.medium))
                                        Text(req.description)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            if !installCommands.isEmpty {
                                ForEach(installCommands, id: \.self) { cmd in
                                    HStack(spacing: 8) {
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.tertiary)
                                        Text(cmd)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Button {
                                installDependencies()
                            } label: {
                                HStack {
                                    Spacer()
                                    if isInstallingDeps {
                                        ProgressView()
                                    } else if depsInstalled {
                                        Label("Setup Queued", systemImage: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    } else {
                                        Label("Install Dependencies", systemImage: "arrow.down.circle.fill")
                                    }
                                    Spacer()
                                }
                                .font(.headline)
                            }
                            .disabled(isInstallingDeps || depsInstalled)
                        }
                    }
                }
            }
            .navigationTitle("Configure \(skill.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved || depsInstalled ? "Done" : "Cancel") { dismiss() }
                }
            }
            .task {
                await loadRequirements()
            }
        }
    }

    private var hasAnyInput: Bool {
        credentialInputs.values.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func fieldBinding(for key: String) -> Binding<String> {
        Binding(
            get: { credentialInputs[key, default: ""] },
            set: { credentialInputs[key] = $0 }
        )
    }

    private func loadRequirements() async {
        isLoadingRequirements = true
        defer { isLoadingRequirements = false }
        do {
            let response = try await agentService.fetchSkillRequirements(
                agentId: agentId,
                skillId: skill.skillId
            )
            requirements = response.requirements
            installCommands = response.installCommands
        } catch {
            // Fall back to config-based env keys
        }
    }

    private func saveCredentials() {
        let creds = credentialInputs
            .filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !creds.isEmpty else { return }

        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await agentService.setSkillCredentials(
                    agentId: agentId,
                    skillId: skill.skillId,
                    credentials: creds
                )
                withAnimation { saved = true }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func installDependencies() {
        isInstallingDeps = true
        errorMessage = nil
        Task {
            do {
                let response = try await agentService.setupSkill(
                    agentId: agentId,
                    skillId: skill.skillId
                )
                setupTaskId = response.setupTaskId
                withAnimation { depsInstalled = true }
            } catch {
                errorMessage = error.localizedDescription
            }
            isInstallingDeps = false
        }
    }
}
