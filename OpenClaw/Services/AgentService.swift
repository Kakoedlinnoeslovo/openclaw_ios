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

    // MARK: - Skill Management

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

    func installClawHubSkill(agentId: String, slug: String) async throws -> ClawHubInstallResponse {
        struct ClawHubBody: Codable { let slug: String }
        let response: ClawHubInstallResponse = try await APIClient.shared.post(
            "/agents/\(agentId)/skills/clawhub",
            body: ClawHubBody(slug: slug)
        )
        if let index = agents.firstIndex(where: { $0.id == agentId }) {
            agents[index] = response.agent
        }
        return response
    }

    func setSkillCredentials(agentId: String, skillId: String, credentials: [String: String]) async throws {
        struct CredBody: Codable { let credentials: [String: String] }
        let _: EmptyResult = try await APIClient.shared.post(
            "/agents/\(agentId)/skills/\(skillId)/credentials",
            body: CredBody(credentials: credentials)
        )
    }

    func removeSkill(agentId: String, skillId: String) async throws {
        try await APIClient.shared.delete("/agents/\(agentId)/skills/\(skillId)")
        if let index = agents.firstIndex(where: { $0.id == agentId }),
           let skillIndex = agents[index].skills.firstIndex(where: { $0.skillId == skillId }) {
            agents[index].skills.remove(at: skillIndex)
        }
    }

    func setSkillEnabled(agentId: String, skillId: String, enabled: Bool) async throws -> Agent {
        struct ToggleBody: Codable { let enabled: Bool }
        let updated: Agent = try await APIClient.shared.patch(
            "/agents/\(agentId)/skills/\(skillId)",
            body: ToggleBody(enabled: enabled)
        )
        if let index = agents.firstIndex(where: { $0.id == agentId }) {
            agents[index] = updated
        }
        return updated
    }

    func updateSkillConfig(agentId: String, skillId: String, config: [String: AnyCodableValue]) async throws -> Agent {
        struct ConfigBody: Codable { let config: [String: AnyCodableValue] }
        let updated: Agent = try await APIClient.shared.patch(
            "/agents/\(agentId)/skills/\(skillId)",
            body: ConfigBody(config: config)
        )
        if let index = agents.firstIndex(where: { $0.id == agentId }) {
            agents[index] = updated
        }
        return updated
    }

    // MARK: - Agent Skills (standalone endpoint)

    func fetchAgentSkills(agentId: String) async throws -> [Agent.InstalledSkill] {
        struct SkillsResponse: Codable { let skills: [Agent.InstalledSkill] }
        let response: SkillsResponse = try await APIClient.shared.get("/agents/\(agentId)/skills")
        if let index = agents.firstIndex(where: { $0.id == agentId }) {
            agents[index].skills = response.skills
        }
        return response.skills
    }

    // MARK: - Skill Setup (install CLI dependencies)

    func setupSkill(agentId: String, skillId: String) async throws -> SkillSetupResponse {
        try await APIClient.shared.post("/agents/\(agentId)/skills/\(skillId)/setup")
    }
}

// MARK: - Response Types

struct ClawHubInstallResponse: Codable {
    let agent: Agent
    let setupRequired: Bool?
    let setupRequirements: [SkillSetupRequirement]?
    let setupTaskId: String?

    init(from decoder: Decoder) throws {
        let agentFields = try Agent(from: decoder)
        self.agent = agentFields

        let container = try decoder.container(keyedBy: ExtraKeys.self)
        self.setupRequired = try container.decodeIfPresent(Bool.self, forKey: .setupRequired)
        self.setupRequirements = try container.decodeIfPresent([SkillSetupRequirement].self, forKey: .setupRequirements)
        self.setupTaskId = try container.decodeIfPresent(String.self, forKey: .setupTaskId)
    }

    private enum ExtraKeys: String, CodingKey {
        case setupRequired
        case setupRequirements
        case setupTaskId
    }
}

struct SkillSetupRequirement: Codable, Identifiable {
    let type: String
    let key: String
    let label: String
    let description: String
    let sensitive: Bool

    var id: String { key }
}

struct SkillSetupResponse: Codable {
    let status: String
    let setupTaskId: String?
    let installCommands: [String]?
    let message: String?
}

private struct EmptyResult: Codable {}
