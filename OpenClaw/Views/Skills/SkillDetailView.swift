import SwiftUI

struct SkillDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionService.self) private var subscription
    @Environment(AppTheme.self) private var theme

    let skill: Skill
    var agentId: String?

    @State private var isInstalling = false
    @State private var showPaywall = false
    @State private var installed = false
    @State private var showAgentPicker = false
    @State private var showCreateAgent = false
    @State private var agentService = AgentService.shared
    @State private var pendingInstallAfterPurchase = false
    @State private var pendingInstallAfterCreation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    statsRow

                    descriptionSection

                    permissionsSection

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
            .sheet(isPresented: $showPaywall, onDismiss: handlePaywallDismiss) {
                PaywallView()
            }
            .sheet(isPresented: $showAgentPicker) {
                agentPickerSheet
            }
            .sheet(isPresented: $showCreateAgent, onDismiss: handleCreateAgentDismiss) {
                AgentCreationView()
            }
            .task {
                if agentId == nil {
                    try? await agentService.fetchAgents()
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: skill.category.icon)
                .font(.system(size: 40))
                .foregroundStyle(theme.accent)
                .frame(width: 80, height: 80)
                .background(theme.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 20))

            VStack(spacing: 4) {
                Text(skill.name)
                    .font(.title3.weight(.semibold))

                Text("by \(skill.author)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                if skill.isCurated {
                    Label("Curated", systemImage: "checkmark.seal.fill")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.accent.opacity(0.1))
                        .foregroundStyle(theme.accent)
                        .clipShape(Capsule())
                }

                Text("v\(skill.version)")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .clipShape(Capsule())
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

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions")
                .font(.headline)

            ForEach(skill.permissions, id: \.self) { permission in
                HStack(spacing: 8) {
                    Image(systemName: "shield.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(permission)
                        .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var needsProUpgrade: Bool {
        skill.requiresPro && subscription.currentTier == .free
    }

    private var installButton: some View {
        Button {
            if needsProUpgrade {
                pendingInstallAfterPurchase = true
                showPaywall = true
                return
            }
            beginInstall()
        } label: {
            HStack {
                if isInstalling {
                    ProgressView()
                        .tint(.white)
                } else if installed {
                    Label("Installed", systemImage: "checkmark")
                } else if needsProUpgrade {
                    Label("Unlock with Pro", systemImage: "lock.fill")
                } else if agentId == nil && agentService.agents.isEmpty {
                    Label("Create Agent & Install", systemImage: "plus.circle.fill")
                } else {
                    Label("Install Skill", systemImage: "arrow.down.circle.fill")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(needsProUpgrade ? Color(.systemGray3) : theme.accent)
        .disabled(isInstalling || installed)
    }

    private var agentPickerSheet: some View {
        NavigationStack {
            List(agentService.agents) { agent in
                Button {
                    showAgentPicker = false
                    installSkill(for: agent.id)
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
                    ContentUnavailableView {
                        Label("No Agents", systemImage: "cpu")
                    } description: {
                        Text("Create an agent first to install skills.")
                    } actions: {
                        Button("Create Agent") {
                            showAgentPicker = false
                            pendingInstallAfterCreation = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                showCreateAgent = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func handlePaywallDismiss() {
        guard pendingInstallAfterPurchase else { return }
        pendingInstallAfterPurchase = false

        if subscription.currentTier != .free {
            beginInstall()
        }
    }

    private func beginInstall() {
        if let agentId {
            installSkill(for: agentId)
        } else if agentService.agents.isEmpty {
            pendingInstallAfterCreation = true
            showCreateAgent = true
        } else {
            showAgentPicker = true
        }
    }

    private func handleCreateAgentDismiss() {
        guard pendingInstallAfterCreation else { return }
        pendingInstallAfterCreation = false

        if let newAgent = agentService.agents.last {
            installSkill(for: newAgent.id)
        }
    }

    private func installSkill(for targetAgentId: String) {
        isInstalling = true
        Task {
            _ = try? await AgentService.shared.installSkill(agentId: targetAgentId, skillId: skill.id)
            isInstalling = false
            installed = true
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1000 {
            return "\(count / 1000).\((count % 1000) / 100)k"
        }
        return "\(count)"
    }
}
