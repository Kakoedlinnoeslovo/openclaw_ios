import SwiftUI

struct UsageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionService.self) private var subscription

    var body: some View {
        NavigationStack {
            List {
                if let usage = subscription.usage {
                    Section("Today") {
                        UsageRow(
                            title: "Tasks",
                            current: usage.tasksToday,
                            limit: usage.tasksLimit,
                            icon: "bolt.fill"
                        )

                        UsageRow(
                            title: "Tokens",
                            current: usage.tokensUsed,
                            limit: usage.tokensLimit,
                            icon: "text.word.spacing"
                        )
                    }

                    Section("Resources") {
                        UsageRow(
                            title: "Agents",
                            current: usage.agentCount,
                            limit: usage.agentLimit,
                            icon: "cpu"
                        )

                        UsageRow(
                            title: "Skills",
                            current: usage.skillCount,
                            limit: usage.skillLimit,
                            icon: "puzzlepiece.fill"
                        )
                    }
                } else {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                try? await subscription.fetchUsage()
            }
        }
    }
}

private struct UsageRow: View {
    let title: String
    let current: Int
    let limit: Int
    let icon: String

    private var progress: Double {
        guard limit > 0 else { return 0 }
        return min(Double(current) / Double(limit), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(current) / \(limit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .tint(progress > 0.9 ? .red : .accent)
        }
        .padding(.vertical, 4)
    }
}
