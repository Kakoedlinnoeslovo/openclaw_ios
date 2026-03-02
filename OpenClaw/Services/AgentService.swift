import Foundation

@Observable
final class AgentService {
    static let shared = AgentService()

    var agents: [Agent] = []
    var isLoading = false

    private init() {}

    func fetchAgents() async throws {
        isLoading = true
        defer { isLoading = false }

        struct AgentsResponse: Codable { let agents: [Agent] }
        let response: AgentsResponse = try await APIClient.shared.get("/agents")
        agents = response.agents
    }

    func createAgent(_ request: CreateAgentRequest) async throws -> Agent {
        let agent: Agent = try await APIClient.shared.post("/agents", body: request)
        agents.append(agent)
        return agent
    }

    func updateAgent(_ id: String, name: String? = nil, persona: AgentPersona? = nil, model: LLMModel? = nil) async throws -> Agent {
        struct UpdateBody: Codable {
            let name: String?
            let persona: AgentPersona?
            let model: LLMModel?
        }
        let updated: Agent = try await APIClient.shared.patch(
            "/agents/\(id)",
            body: UpdateBody(name: name, persona: persona, model: model)
        )
        if let index = agents.firstIndex(where: { $0.id == id }) {
            agents[index] = updated
        }
        return updated
    }

    func deleteAgent(_ id: String) async throws {
        try await APIClient.shared.delete("/agents/\(id)")
        agents.removeAll { $0.id == id }
    }

    func installSkill(agentId: String, skillId: String) async throws -> Agent {
        struct InstallBody: Codable { let skillId: String }
        let updated: Agent = try await APIClient.shared.post(
            "/agents/\(agentId)/skills",
            body: InstallBody(skillId: skillId)
        )
        if let index = agents.firstIndex(where: { $0.id == agentId }) {
            agents[index] = updated
        }
        return updated
    }

    func removeSkill(agentId: String, skillId: String) async throws {
        try await APIClient.shared.delete("/agents/\(agentId)/skills/\(skillId)")
        if let index = agents.firstIndex(where: { $0.id == agentId }),
           let skillIndex = agents[index].skills.firstIndex(where: { $0.skillId == skillId }) {
            agents[index].skills.remove(at: skillIndex)
        }
    }
}
