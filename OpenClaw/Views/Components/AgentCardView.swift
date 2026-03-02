import SwiftUI

struct AgentCardView: View {
    @Environment(AppTheme.self) private var theme
    let agent: Agent

    private var iconGradient: LinearGradient {
        let colors: [Color] = switch agent.persona {
        case .professional: [.blue, .cyan]
        case .friendly: [.teal, .cyan]
        case .technical: [.purple, .indigo]
        case .creative: [.pink, .orange]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: agent.persona.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(iconGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(agent.name)
                        .font(.subheadline.weight(.semibold))

                    if agent.model.requiresPro {
                        Text("PRO")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                LinearGradient(
                                    colors: theme.accentGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    Text(agent.model.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !agent.skills.isEmpty {
                        Text("·")
                            .foregroundStyle(.quaternary)
                        HStack(spacing: 2) {
                            Image(systemName: "puzzlepiece.fill")
                                .font(.system(size: 9))
                            Text("\(agent.skills.count)")
                                .font(.caption)
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(agent.isActive ? theme.accent : .gray.opacity(0.4))
                        .frame(width: 7, height: 7)
                    Text(agent.isActive ? "Active" : "Idle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(agent.isActive ? theme.accent : .secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
