import SwiftUI

struct ClawHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTheme.self) private var theme

    var initialPath: String?
    var agentId: String?

    @State private var agentService = AgentService.shared
    @State private var skillService = SkillService.shared
    @State private var oauthService = OAuthService.shared
    @State private var searchText = ""
    @State private var selectedCategory: SkillCategory?
    @State private var selectedSkill: Skill?

    @State private var installState: InstallState = .idle
    @State private var installingSlug: String?
    @State private var installedSkillId: String?
    @State private var installError: String?
    @State private var installWarning: String?
    @State private var setupRequirements: [SkillSetupRequirement] = []
    @State private var oauthProvider: OAuthProvider?
    @State private var showAgentPicker = false
    @State private var pendingSkill: Skill?
    @State private var targetAgentId: String?
    @State private var credentialInputs: [String: String] = [:]
    @State private var isSavingCredentials = false
    @State private var credentialsSaved = false
    @State private var showOAuthSetup = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryPicker

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        if skillService.isLoadingClawHub && skillService.clawHubSkills.isEmpty {
                            ProgressView()
                                .padding(.top, 40)
                        } else if skillService.clawHubSkills.isEmpty && !searchText.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        } else {
                            ForEach(skillService.clawHubSkills) { skill in
                                clawHubSkillCard(skill)
                                    .onTapGesture { selectedSkill = skill }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Community Skills")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search community skills")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedSkill) { skill in
                ClawHubSkillDetailView(skill: skill, agentId: agentId)
            }
            .sheet(isPresented: $showAgentPicker) {
                agentPickerSheet
            }
            .sheet(isPresented: $showOAuthSetup) {
                NavigationStack {
                    GoogleOAuthConfigView(isConfigured: false) {
                        showOAuthSetup = false
                    }
                }
            }
            .overlay {
                if installState == .installing || installState == .success || installState == .failed || installState == .needsSetup {
                    installProgressOverlay
                        .transition(.opacity)
                }
            }
            .animation(.spring(duration: 0.3), value: installState)
            .task {
                try? await agentService.fetchAgents()
                try? await skillService.fetchClawHubCatalog(agentId: agentId)
            }
            .onChange(of: searchText) {
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    try? await skillService.fetchClawHubCatalog(
                        category: selectedCategory,
                        search: searchText.isEmpty ? nil : searchText,
                        agentId: agentId
                    )
                }
            }
        }
    }

    // MARK: - Skill Card

    private func clawHubSkillCard(_ skill: Skill) -> some View {
        HStack(spacing: 14) {
            Image(systemName: skill.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(
                    LinearGradient(
                        colors: [.orange, .red.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .font(.subheadline.weight(.semibold))

                    Text("ClawHub")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.orange)
                        .clipShape(Capsule())
                }

                Text(skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if skill.isInstalled == true {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)
            } else {
                Button {
                    beginInstall(skill)
                } label: {
                    Text("Get")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(theme.accent.opacity(0.12))
                        .clipShape(Capsule())
                }
                .disabled(installState == .installing)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(nil, label: "All")
                ForEach(SkillCategory.allCases) { cat in
                    categoryChip(cat, label: cat.rawValue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    private func categoryChip(_ category: SkillCategory?, label: String) -> some View {
        let isSelected = selectedCategory == category

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = category
            }
            Task {
                try? await skillService.fetchClawHubCatalog(
                    category: category,
                    search: searchText.isEmpty ? nil : searchText,
                    agentId: agentId
                )
            }
        } label: {
            HStack(spacing: 5) {
                if let cat = category {
                    Image(systemName: cat.icon)
                        .font(.system(size: 11))
                }
                Text(label)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? .orange : Color(.secondarySystemGroupedBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }

    // MARK: - Install Logic

    private func beginInstall(_ skill: Skill) {
        pendingSkill = skill
        if let agentId {
            installSkill(skill, agentId: agentId)
        } else if agentService.agents.count == 1 {
            installSkill(skill, agentId: agentService.agents[0].id)
        } else {
            showAgentPicker = true
        }
    }

    private func installSkill(_ skill: Skill, agentId: String) {
        guard let slug = skill.slug else { return }
        installState = .installing
        installingSlug = slug
        installedSkillId = nil
        installError = nil
        installWarning = nil
        oauthProvider = nil
        targetAgentId = agentId
        credentialInputs = [:]
        credentialsSaved = false

        Task {
            do {
                let result = try await agentService.installClawHubSkill(agentId: agentId, slug: slug)
                agentService.lastActiveAgentId = agentId
                installWarning = result.installWarning

                let skillId = slug.split(separator: "/").last.map(String.init) ?? slug
                installedSkillId = skillId

                if let provider = OAuthProvider.provider(forSkillId: skillId) {
                    oauthProvider = provider
                    installState = .needsSetup
                } else if result.setupRequired == true, let reqs = result.setupRequirements, !reqs.isEmpty {
                    setupRequirements = reqs
                    installState = .needsSetup
                } else {
                    installState = .success
                }
                try? await skillService.fetchClawHubCatalog(
                    category: selectedCategory,
                    search: searchText.isEmpty ? nil : searchText,
                    agentId: self.agentId
                )
            } catch {
                installError = error.localizedDescription
                installState = .failed
            }
        }
    }

    // MARK: - OAuth Connect

    private func connectOAuth(provider: OAuthProvider, agentId: String) {
        guard let skillId = installedSkillId else { return }
        Task {
            do {
                let success = try await oauthService.startOAuthFlow(
                    provider: provider,
                    agentId: agentId,
                    skillId: skillId
                )
                if success {
                    withAnimation {
                        installState = .success
                        oauthProvider = nil
                    }
                }
            } catch OAuthError.notConfigured {
                showOAuthSetup = true
            } catch {
                // Error is stored in oauthService.lastError
            }
        }
    }

    // MARK: - Agent Picker

    private var agentPickerSheet: some View {
        NavigationStack {
            List(agentService.agents) { agent in
                Button {
                    showAgentPicker = false
                    if let skill = pendingSkill {
                        installSkill(skill, agentId: agent.id)
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
                            if let slug = installingSlug {
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
                            if let warning = installWarning {
                                Text(warning)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    case .needsSetup:
                        if let provider = oauthProvider, let targetAgentId = agentId ?? agentService.agents.first?.id {
                            VStack(spacing: 16) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.green)
                                Text("Skill installed!")
                                    .font(.headline)
                                Text("Connect your \(provider.displayName) account to get started.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)

                                Button {
                                    connectOAuth(provider: provider, agentId: targetAgentId)
                                } label: {
                                    HStack(spacing: 8) {
                                        if oauthService.isAuthenticating {
                                            ProgressView()
                                                .tint(.white)
                                        } else {
                                            Image(systemName: provider.iconName)
                                            Text("Connect to \(provider.displayName)")
                                        }
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                .disabled(oauthService.isAuthenticating)

                                if let error = oauthService.lastError {
                                    Text(error)
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        } else {
                            credentialSetupSection
                        }
                    case .failed:
                        VStack(spacing: 12) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.red)
                            Text("Installation failed")
                                .font(.headline)
                            if let error = installError {
                                Text(error)
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

                if installState == .success || installState == .failed || installState == .needsSetup {
                    Button {
                        withAnimation {
                            installState = .idle
                            installError = nil
                            installWarning = nil
                            setupRequirements = []
                            oauthProvider = nil
                            installedSkillId = nil
                            targetAgentId = nil
                            credentialInputs = [:]
                            credentialsSaved = false
                        }
                    } label: {
                        let label: String = if installState == .failed {
                            "Dismiss"
                        } else if oauthProvider != nil || (!setupRequirements.isEmpty && !credentialsSaved) {
                            "Skip for Now"
                        } else {
                            "Done"
                        }
                        Text(label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(installState == .success || credentialsSaved ? Color.green : installState == .needsSetup ? .orange : theme.accent)
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

    // MARK: - Credential Setup

    private var credentialSetupSection: some View {
        VStack(spacing: 12) {
            if credentialsSaved {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                Text("Configured!")
                    .font(.headline)
                Text("Credentials saved. The skill is ready to use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "key.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                Text("Setup Required")
                    .font(.headline)
                Text("Enter the credentials this skill needs to work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                let envRequirements = setupRequirements.filter { $0.type == "env" }
                ForEach(envRequirements) { req in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(req.label)
                            .font(.caption.weight(.medium))

                        if req.sensitive {
                            SecureField(req.key, text: binding(for: req.key))
                                .textFieldStyle(.roundedBorder)
                                .font(.subheadline.monospaced())
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            TextField(req.key, text: binding(for: req.key))
                                .textFieldStyle(.roundedBorder)
                                .font(.subheadline.monospaced())
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }
                }

                let nonEnvRequirements = setupRequirements.filter { $0.type != "env" }
                ForEach(nonEnvRequirements) { req in
                    HStack(spacing: 8) {
                        Image(systemName: "wrench.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(req.label)
                                .font(.caption.weight(.medium))
                            Text(req.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if !envRequirements.isEmpty {
                    Button {
                        saveCredentials()
                    } label: {
                        HStack(spacing: 8) {
                            if isSavingCredentials {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.shield.fill")
                                Text("Save & Configure")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(hasAllCredentials ? .blue : .gray)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!hasAllCredentials || isSavingCredentials)
                }
            }
        }
    }

    private var hasAllCredentials: Bool {
        let envKeys = setupRequirements.filter { $0.type == "env" }.map(\.key)
        return envKeys.allSatisfy { key in
            guard let value = credentialInputs[key] else { return false }
            return !value.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { credentialInputs[key, default: ""] },
            set: { credentialInputs[key] = $0 }
        )
    }

    private func saveCredentials() {
        guard let skillId = installedSkillId,
              let agentId = targetAgentId ?? agentId ?? agentService.agents.first?.id else { return }

        let envCredentials = credentialInputs
            .filter { key, value in
                setupRequirements.contains(where: { $0.type == "env" && $0.key == key })
                && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !envCredentials.isEmpty else { return }

        isSavingCredentials = true
        Task {
            do {
                try await agentService.setSkillCredentials(
                    agentId: agentId,
                    skillId: skillId,
                    credentials: envCredentials
                )
                withAnimation {
                    credentialsSaved = true
                }
            } catch {
                installError = error.localizedDescription
            }
            isSavingCredentials = false
        }
    }
}

// MARK: - Install State

private enum InstallState: Equatable {
    case idle
    case installing
    case success
    case needsSetup
    case failed
}

// MARK: - ClawHub Skill Detail

struct ClawHubSkillDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTheme.self) private var theme

    let skill: Skill
    var agentId: String?

    @State private var agentService = AgentService.shared
    @State private var oauthService = OAuthService.shared
    @State private var isInstalling = false
    @State private var installed = false
    @State private var oauthConnected = false
    @State private var showAgentPicker = false
    @State private var installError: String?
    @State private var setupRequirements: [SkillSetupRequirement] = []
    @State private var showSetupSheet = false
    @State private var credentialInputs: [String: String] = [:]
    @State private var isSavingCredentials = false
    @State private var credentialsSaved = false
    @State private var installedAgentId: String?
    @State private var showOAuthSetup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    statsRow
                    descriptionSection
                    installButton

                    if installed && !setupRequirements.isEmpty && oauthProvider == nil {
                        credentialSetupInline
                    }
                }
                .padding()
            }
            .navigationTitle(skill.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showAgentPicker) {
                agentPickerSheet
            }
            .sheet(isPresented: $showOAuthSetup) {
                NavigationStack {
                    GoogleOAuthConfigView(isConfigured: false) {
                        showOAuthSetup = false
                    }
                }
            }
            .alert("Installation Failed", isPresented: .constant(installError != nil)) {
                Button("OK") { installError = nil }
            } message: {
                Text(installError ?? "")
            }
            .task {
                if agentId == nil {
                    try? await agentService.fetchAgents()
                }
                checkInstalledState()
                if installed, let targetAgentId = agentId ?? agentService.agents.first?.id {
                    await checkOAuthStatus(agentId: targetAgentId)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: skill.icon)
                .font(.system(size: 40))
                .foregroundStyle(.white)
                .frame(width: 80, height: 80)
                .background(
                    LinearGradient(
                        colors: [.orange, .red.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))

            VStack(spacing: 4) {
                Text(skill.name)
                    .font(.title3.weight(.semibold))

                Text("by \(skill.author)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Label("Community", systemImage: "globe.americas.fill")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.1))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())

                Text("v\(skill.version)")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .clipShape(Capsule())

                if installed {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.1))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
            }

            if let slug = skill.slug {
                Text(slug)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statItem(value: formatCount(skill.downloads), label: "Downloads")
            Divider().frame(height: 32)
            statItem(value: "\(skill.stars)", label: "Stars")
            Divider().frame(height: 32)
            statItem(value: skill.category.rawValue, label: "Category")
        }
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.headline)

            Text(skill.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var oauthProvider: OAuthProvider? {
        guard let slug = skill.slug else { return nil }
        let skillId = slug.split(separator: "/").last.map(String.init) ?? slug
        return OAuthProvider.provider(forSkillId: skillId)
    }

    private var installButton: some View {
        Group {
            if !installed {
                Button {
                    beginInstall()
                } label: {
                    HStack {
                        if isInstalling {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Label("Install Skill", systemImage: "arrow.down.circle.fill")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isInstalling)
            } else if let provider = oauthProvider, !oauthConnected {
                VStack(spacing: 12) {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)

                    Button {
                        connectOAuth(provider: provider)
                    } label: {
                        HStack(spacing: 8) {
                            if oauthService.isAuthenticating {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: provider.iconName)
                                Text("Connect to \(provider.displayName)")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(oauthService.isAuthenticating)

                    if let error = oauthService.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
            } else {
                VStack(spacing: 4) {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    if oauthConnected {
                        Label("Connected", systemImage: "link.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        }
    }

    private var agentPickerSheet: some View {
        NavigationStack {
            List(agentService.agents) { agent in
                Button {
                    showAgentPicker = false
                    installSkill(agentId: agent.id)
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
            .navigationTitle("Choose Agent")
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

    private func checkInstalledState() {
        installed = skill.isInstalled ?? false
    }

    private func beginInstall() {
        if let agentId {
            installSkill(agentId: agentId)
        } else if agentService.agents.count == 1 {
            installSkill(agentId: agentService.agents[0].id)
        } else {
            showAgentPicker = true
        }
    }

    private func installSkill(agentId: String) {
        guard let slug = skill.slug else { return }
        isInstalling = true
        installError = nil
        installedAgentId = agentId
        credentialInputs = [:]
        credentialsSaved = false

        Task {
            do {
                let result = try await agentService.installClawHubSkill(agentId: agentId, slug: slug)
                agentService.lastActiveAgentId = agentId
                if result.setupRequired == true, let reqs = result.setupRequirements, !reqs.isEmpty {
                    setupRequirements = reqs
                }
                installed = true
                await checkOAuthStatus(agentId: agentId)
            } catch {
                installError = error.localizedDescription
            }
            isInstalling = false
        }
    }

    private func connectOAuth(provider: OAuthProvider) {
        guard let targetAgentId = agentId ?? agentService.agents.first?.id,
              let slug = skill.slug else { return }
        let skillId = slug.split(separator: "/").last.map(String.init) ?? slug

        Task {
            do {
                let success = try await oauthService.startOAuthFlow(
                    provider: provider,
                    agentId: targetAgentId,
                    skillId: skillId
                )
                if success {
                    oauthConnected = true
                }
            } catch OAuthError.notConfigured {
                showOAuthSetup = true
            } catch {
                // Error is stored in oauthService.lastError
            }
        }
    }

    private func checkOAuthStatus(agentId: String) async {
        guard let slug = skill.slug else { return }
        let skillId = slug.split(separator: "/").last.map(String.init) ?? slug
        guard OAuthProvider.provider(forSkillId: skillId) != nil else { return }

        if let status = try? await oauthService.checkStatus(agentId: agentId, skillId: skillId) {
            oauthConnected = status.connected
        }
    }

    // MARK: - Credential Setup (Detail View)

    private var credentialSetupInline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(credentialsSaved ? "Configured" : "Setup Required",
                  systemImage: credentialsSaved ? "checkmark.shield.fill" : "key.circle.fill")
                .font(.headline)
                .foregroundStyle(credentialsSaved ? .green : .orange)

            if !credentialsSaved {
                Text("Enter the credentials this skill needs to work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let envRequirements = setupRequirements.filter { $0.type == "env" }
            ForEach(envRequirements) { req in
                VStack(alignment: .leading, spacing: 4) {
                    Text(req.label)
                        .font(.caption.weight(.medium))
                    if req.sensitive {
                        SecureField(req.key, text: detailBinding(for: req.key))
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline.monospaced())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .disabled(credentialsSaved)
                    } else {
                        TextField(req.key, text: detailBinding(for: req.key))
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline.monospaced())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .disabled(credentialsSaved)
                    }
                }
            }

            if !envRequirements.isEmpty && !credentialsSaved {
                Button {
                    saveDetailCredentials()
                } label: {
                    HStack(spacing: 8) {
                        if isSavingCredentials {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.shield.fill")
                            Text("Save & Configure")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(detailHasAllCredentials ? .blue : .gray)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!detailHasAllCredentials || isSavingCredentials)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var detailHasAllCredentials: Bool {
        let envKeys = setupRequirements.filter { $0.type == "env" }.map(\.key)
        return envKeys.allSatisfy { key in
            guard let value = credentialInputs[key] else { return false }
            return !value.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func detailBinding(for key: String) -> Binding<String> {
        Binding(
            get: { credentialInputs[key, default: ""] },
            set: { credentialInputs[key] = $0 }
        )
    }

    private func saveDetailCredentials() {
        guard let slug = skill.slug else { return }
        let skillId = slug.split(separator: "/").last.map(String.init) ?? slug
        guard let targetAgentId = installedAgentId ?? agentId ?? agentService.agents.first?.id else { return }

        let envCredentials = credentialInputs
            .filter { key, value in
                setupRequirements.contains(where: { $0.type == "env" && $0.key == key })
                && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !envCredentials.isEmpty else { return }

        isSavingCredentials = true
        Task {
            do {
                try await agentService.setSkillCredentials(
                    agentId: targetAgentId,
                    skillId: skillId,
                    credentials: envCredentials
                )
                withAnimation {
                    credentialsSaved = true
                }
            } catch {
                installError = error.localizedDescription
            }
            isSavingCredentials = false
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1000 {
            return "\(count / 1000).\((count % 1000) / 100)k"
        }
        return "\(count)"
    }
}
