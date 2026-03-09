import Foundation

@Observable
final class SkillService {
    static let shared = SkillService()

    var skills: [Skill] = []
    var clawHubSkills: [Skill] = []
    var recommendedSkills: [Skill] = []
    var categories: [SkillCategory] = SkillCategory.allCases
    var isLoading = false
    var isLoadingClawHub = false

    private init() {}

    func fetchCatalog(category: SkillCategory? = nil, search: String? = nil, agentId: String? = nil) async throws {
        isLoading = true
        defer { isLoading = false }

        var path = "/skills/catalog?"
        if let category { path += "category=\(category.rawValue)&" }
        if let search, !search.isEmpty { path += "q=\(search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search)&" }
        if let agentId { path += "agent_id=\(agentId)&" }

        let response: SkillCatalogResponse = try await APIClient.shared.get(path)
        skills = response.skills
    }

    func fetchClawHubCatalog(category: SkillCategory? = nil, search: String? = nil, agentId: String? = nil) async throws {
        isLoadingClawHub = true
        defer { isLoadingClawHub = false }

        var path = "/skills/clawhub/browse?"
        if let category { path += "category=\(category.rawValue)&" }
        if let search, !search.isEmpty { path += "q=\(search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search)&" }
        if let agentId { path += "agent_id=\(agentId)&" }

        let response: ClawHubCatalogResponse = try await APIClient.shared.get(path)
        clawHubSkills = response.skills
    }

    func getSkillDetail(_ id: String) async throws -> Skill {
        try await APIClient.shared.get("/skills/\(id)")
    }

    func fetchRecommended(agentId: String? = nil) async throws {
        var path = "/skills/recommended?"
        if let agentId { path += "agent_id=\(agentId)&" }

        let response: RecommendedSkillsResponse = try await APIClient.shared.get(path)
        recommendedSkills = response.skills
    }
}

struct ClawHubCatalogResponse: Codable {
    let skills: [Skill]
    let totalCount: Int
}
