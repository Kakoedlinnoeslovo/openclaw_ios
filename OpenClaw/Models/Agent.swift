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
        let version: String
        var isEnabled: Bool
        let source: String
        let config: [String: AnyCodableValue]?
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
        false
    }
}

struct CreateAgentRequest: Codable {
    let name: String
    let persona: AgentPersona
    let model: LLMModel
}

// Type-erased JSON value for skill config
enum AnyCodableValue: Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else { self = .string("") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        }
    }
}
