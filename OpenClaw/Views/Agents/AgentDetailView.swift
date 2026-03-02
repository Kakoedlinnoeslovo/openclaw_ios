import SwiftUI

struct AgentDetailView: View {
    @Environment(AppTheme.self) private var theme
    let agent: Agent

    @State private var showSkillBrowser = false
    @State private var showChat = false

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
            Text("Installed Skills")
                .font(.headline)

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
                    HStack(spacing: 12) {
                        Image(systemName: skill.icon)
                            .font(.body)
                            .foregroundStyle(theme.accent)
                            .frame(width: 36, height: 36)
                            .background(theme.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text(skill.name)
                            .font(.subheadline.weight(.medium))

                        Spacer()

                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.accent)
                            .font(.subheadline)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
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
