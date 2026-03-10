import SwiftUI

struct AgentCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionService.self) private var subscription

    var onCreated: ((Agent) -> Void)?

    @State private var name = ""
    @State private var persona: AgentPersona = .professional
    @State private var model: LLMModel = .gpt52
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Agent name", text: $name)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Give your agent a memorable name")
                }

                Section("Personality") {
                    ForEach(AgentPersona.allCases) { p in
                        Button {
                            persona = p
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: p.icon)
                                    .font(.title3)
                                    .foregroundStyle(.accent)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.rawValue)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(p.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if persona == p {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.accent)
                                }
                            }
                        }
                    }
                }

                Section("AI Model") {
                    ForEach(LLMModel.allCases) { m in
                        Button {
                            if m.requiresPro && subscription.currentTier == .free {
                                showPaywall = true
                            } else {
                                model = m
                            }
                        } label: {
                            HStack {
                                Text(m.displayName)
                                    .foregroundStyle(.primary)

                                if m.requiresPro {
                                    Text("PRO")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.accent.opacity(0.15))
                                        .foregroundStyle(.accent)
                                        .clipShape(Capsule())
                                }

                                Spacer()

                                if model == m {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.accent)
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        createAgent()
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    private func createAgent() {
        isCreating = true
        Task {
            do {
                let request = CreateAgentRequest(name: name, persona: persona, model: model)
                let agent = try await AgentService.shared.createAgent(request)
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onCreated?(agent)
                }
            } catch let error as APIError {
                errorMessage = error.errorDescription
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }
}
