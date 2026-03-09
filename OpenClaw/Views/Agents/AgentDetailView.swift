import SwiftUI

struct AgentDetailView: View {
    @Environment(AppTheme.self) private var theme
    @State var agent: Agent

    @State private var showSkillBrowser = false
    @State private var showChat = false
    @State private var agentService = AgentService.shared

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
        .sheet(isPresented: $showSkillBrowser) {
            NavigationStack {
                SkillBrowserView(agentId: agent.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showSkillBrowser = false }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showChat) {
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
                Text("v\(skill.version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

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
