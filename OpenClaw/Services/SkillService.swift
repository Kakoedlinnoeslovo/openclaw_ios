import Foundation

@Observable
final class SkillService {
    static let shared = SkillService()

    var skills: [Skill] = []
    var categories: [SkillCategory] = SkillCategory.allCases
    var isLoading = false

    private init() {}

    func fetchCatalog(category: SkillCategory? = nil, search: String? = nil) async throws {
        isLoading = true
        defer { isLoading = false }

        var path = "/skills/catalog?"
        if let category { path += "category=\(category.rawValue)&" }
        if let search, !search.isEmpty { path += "q=\(search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search)&" }

        let response: SkillCatalogResponse = try await APIClient.shared.get(path)
        skills = response.skills
    }

    func getSkillDetail(_ id: String) async throws -> Skill {
        try await APIClient.shared.get("/skills/\(id)")
    }
}
