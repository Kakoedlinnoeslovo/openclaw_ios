import Foundation

struct Agent: Codable, Identifiable {
    let id: String
    var name: String
    var persona: AgentPersona
    var model: LLMModel
    var skills: [InstalledSkill]
    var isActive: Bool
    let createdAt: Date

    struct InstalledSkill: Codable, Identifiable {
        let id: String
        let skillId: String
        let name: String
        let icon: String
        let installedAt: Date
    }
}

enum AgentPersona: String, Codable, CaseIterable, Identifiable {
    case professional = "Professional"
    case friendly = "Friendly"
    case technical = "Technical"
    case creative = "Creative"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .professional: return "briefcase.fill"
        case .friendly: return "face.smiling.fill"
        case .technical: return "wrench.and.screwdriver.fill"
        case .creative: return "paintpalette.fill"
        }
    }

    var description: String {
        switch self {
        case .professional: return "Clear, concise, business-oriented"
        case .friendly: return "Warm, approachable, conversational"
        case .technical: return "Detailed, precise, data-driven"
        case .creative: return "Imaginative, expressive, open-ended"
        }
    }
}

enum LLMModel: String, Codable, CaseIterable, Identifiable {
    case gpt4oMini = "gpt-4o-mini"
    case gpt4o = "gpt-4o"
    case claude = "claude-sonnet"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt4oMini: return "GPT-4o Mini"
        case .gpt4o: return "GPT-4o"
        case .claude: return "Claude Sonnet"
        }
    }

    var requiresPro: Bool {
        self != .gpt4oMini
    }
}

struct CreateAgentRequest: Codable {
    let name: String
    let persona: AgentPersona
    let model: LLMModel
}
