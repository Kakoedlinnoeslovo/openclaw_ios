import SwiftUI

enum QuickAction: String, CaseIterable, Identifiable {
    case chat = "Chat"
    case create = "Create"
    case research = "Research"
    case email = "Email"
    case write = "Write"
    case web = "Web"
    case vision = "Vision"
    case voice = "Voice"

    var id: String { rawValue }

    var needsInput: Bool {
        switch self {
        case .chat, .create, .voice: false
        default: true
        }
    }

    var icon: String {
        switch self {
        case .chat: "text.bubble.fill"
        case .create: "wand.and.stars"
        case .research: "doc.text.magnifyingglass"
        case .email: "envelope.fill"
        case .write: "pencil.and.outline"
        case .web: "globe"
        case .vision: "camera.fill"
        case .voice: "mic.fill"
        }
    }

    func color(accent: Color) -> Color {
        switch self {
        case .chat: accent
        case .create: .purple
        case .research: .indigo
        case .email: .orange
        case .write: .pink
        case .web: .cyan
        case .vision: .teal
        case .voice: Color(red: 0.45, green: 0.20, blue: 0.95)
        }
    }

    var headerTitle: String {
        switch self {
        case .chat: "Start a Chat"
        case .create: "Create Agent"
        case .research: "Research a Topic"
        case .email: "Draft an Email"
        case .write: "Write Something"
        case .web: "Browse the Web"
        case .vision: "Vision AI"
        case .voice: "Voice Mode"
        }
    }

    var headerSubtitle: String {
        switch self {
        case .chat: "Chat with your AI agent"
        case .create: "Build a custom AI assistant"
        case .research: "Get comprehensive research on any topic"
        case .email: "Compose professional emails effortlessly"
        case .write: "Create any type of written content"
        case .web: "Search and summarize web content"
        case .vision: "Analyze images or generate visual content"
        case .voice: "Talk to your agent in real time"
        }
    }

    var submitLabel: String {
        switch self {
        case .research: "Start Research"
        case .email: "Draft Email"
        case .write: "Start Writing"
        case .web: "Search Web"
        case .vision: "Process"
        case .voice: "Send"
        default: "Go"
        }
    }
}
