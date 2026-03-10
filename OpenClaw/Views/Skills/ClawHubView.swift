import SwiftUI

struct ClawHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTheme.self) private var theme

    var initialPath: String?
    var agentId: String?

    @State private var agentService = AgentService.shared
    @State private var skillService = SkillService.shared
    @State private var searchText = ""
    @State private var selectedCategory: SkillCategory?
    @State private var selectedSkill: Skill?

    @State private var installState: InstallState = .idle
    @State private var installingSlug: String?
    @State private var installError: String?
    @State private var installWarning: String?
    @State private var setupRequirements: [SkillSetupRequirement] = []
    @State private var showAgentPicker = false
    @State private var pendingSkill: Skill?

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
        installError = nil
        installWarning = nil

        Task {
            do {
                let result = try await agentService.installClawHubSkill(agentId: agentId, slug: slug)
                installWarning = result.installWarning
                if result.setupRequired == true, let reqs = result.setupRequirements, !reqs.isEmpty {
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
                        VStack(spacing: 12) {
                            Image(systemName: "gearshape.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.orange)
                            Text("Setup Required")
                                .font(.headline)
                            Text("This skill needs configuration before it can work.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            ForEach(setupRequirements) { req in
                                HStack(spacing: 8) {
                                    Image(systemName: req.sensitive ? "key.fill" : "wrench.fill")
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
                        }
                    } label: {
                        Text(installState == .failed ? "Dismiss" : "Done")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(installState == .success ? Color.green : installState == .needsSetup ? .orange : theme.accent)
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
    @State private var isInstalling = false
    @State private var installed = false
    @State private var showAgentPicker = false
    @State private var installError: String?
    @State private var setupRequirements: [SkillSetupRequirement] = []
    @State private var showSetupInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    statsRow
                    descriptionSection
                    installButton
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
            } else {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
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

        Task {
            do {
                let result = try await agentService.installClawHubSkill(agentId: agentId, slug: slug)
                if result.setupRequired == true, let reqs = result.setupRequirements, !reqs.isEmpty {
                    setupRequirements = reqs
                    showSetupInfo = true
                }
                installed = true
            } catch {
                installError = error.localizedDescription
            }
            isInstalling = false
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1000 {
            return "\(count / 1000).\((count % 1000) / 100)k"
        }
        return "\(count)"
    }
}
