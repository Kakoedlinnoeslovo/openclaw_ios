import Foundation

@Observable
final class AgentService {
    static let shared = AgentService()

    var agents: [Agent] = []
    var isLoading = false

    var lastActiveAgentId: String? {
        get { UserDefaults.standard.string(forKey: "lastActiveAgentId") }
        set { UserDefaults.standard.set(newValue, forKey: "lastActiveAgentId") }
    }

    var preferredAgent: Agent? {
        if let id = lastActiveAgentId,
           let agent = agents.first(where: { $0.id == id }) {
            return agent
        }
        return agents.first
    }

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
        // Refresh the agent so _configured flag and UI update immediately
        try? await fetchAgents()
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

    func fetchSkillRequirements(agentId: String, skillId: String) async throws -> SkillRequirementsResponse {
        try await APIClient.shared.get("/agents/\(agentId)/skills/\(skillId)/requirements")
    }
}

// MARK: - Response Types

struct ClawHubInstallResponse: Codable {
    let agent: Agent
    let setupRequired: Bool?
    let setupRequirements: [SkillSetupRequirement]?
    let setupTaskId: String?
    let installWarning: String?
    let installNote: String?

    private enum CodingKeys: String, CodingKey {
        case agent
        case setupRequired
        case setupRequirements
        case setupTaskId
        case installWarning
        case installNote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let nested = try? container.decode(Agent.self, forKey: .agent) {
            self.agent = nested
        } else {
            self.agent = try Agent(from: decoder)
        }

        self.setupRequired = try container.decodeIfPresent(Bool.self, forKey: .setupRequired)
        self.setupRequirements = try container.decodeIfPresent([SkillSetupRequirement].self, forKey: .setupRequirements)
        self.setupTaskId = try container.decodeIfPresent(String.self, forKey: .setupTaskId)
        self.installWarning = try container.decodeIfPresent(String.self, forKey: .installWarning)
        self.installNote = try container.decodeIfPresent(String.self, forKey: .installNote)
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

struct SkillRequirementsResponse: Codable {
    let skillId: String
    let source: String
    let requirements: [SkillSetupRequirement]
    let installCommands: [String]
    let isConfigured: Bool
}

private struct EmptyResult: Codable {}
