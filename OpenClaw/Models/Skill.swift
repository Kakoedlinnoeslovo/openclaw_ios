import Foundation

struct Skill: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let author: String
    let category: SkillCategory
    let downloads: Int
    let stars: Int
    let version: String
    let isCurated: Bool
    let requiresPro: Bool
    let permissions: [String]
    var isInstalled: Bool?
    let slug: String?
    let source: String?

    var isClawHub: Bool { source == "clawhub" }
}

enum SkillCategory: String, Codable, CaseIterable, Identifiable {
    case productivity = "Productivity"
    case research = "Research"
    case writing = "Writing"
    case data = "Data"
    case communication = "Communication"
    case automation = "Automation"
    case development = "Development"
    case aiMl = "AI/ML"
    case utility = "Utility"
    case web = "Web"
    case science = "Science"
    case media = "Media"
    case social = "Social"
    case finance = "Finance"
    case location = "Location"
    case business = "Business"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .productivity: return "checkmark.circle.fill"
        case .research: return "magnifyingglass.circle.fill"
        case .writing: return "pencil.circle.fill"
        case .data: return "chart.bar.fill"
        case .communication: return "message.circle.fill"
        case .automation: return "gearshape.2.fill"
        case .development: return "chevron.left.forwardslash.chevron.right"
        case .aiMl: return "brain"
        case .utility: return "wrench.fill"
        case .web: return "globe"
        case .science: return "flask.fill"
        case .media: return "play.rectangle.fill"
        case .social: return "person.2.fill"
        case .finance: return "chart.line.uptrend.xyaxis"
        case .location: return "location.fill"
        case .business: return "briefcase.fill"
        }
    }
}

struct SkillCatalogResponse: Codable {
    let skills: [Skill]
    let categories: [SkillCategory]
    let totalCount: Int
}

struct RecommendedSkillsResponse: Codable {
    let skills: [Skill]
    let persona: String
}
