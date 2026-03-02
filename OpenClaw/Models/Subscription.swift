import Foundation

struct SubscriptionInfo: Codable {
    let tier: User.SubscriptionTier
    let expiresAt: Date?
    let isActive: Bool
    let productId: String?
}

struct SubscriptionFeature: Identifiable {
    let id = UUID()
    let title: String
    let freeValue: String
    let proValue: String
    let icon: String
}

extension SubscriptionFeature {
    static let allFeatures: [SubscriptionFeature] = [
        .init(title: "AI Agents", freeValue: "1", proValue: "5", icon: "cpu"),
        .init(title: "Daily Tasks", freeValue: "10", proValue: "100", icon: "bolt.fill"),
        .init(title: "Skills", freeValue: "5 curated", proValue: "All skills", icon: "puzzlepiece.fill"),
        .init(title: "AI Model", freeValue: "GPT-4o Mini", proValue: "GPT-4o & Claude", icon: "brain"),
        .init(title: "Memory", freeValue: "7 days", proValue: "90 days", icon: "memorychip"),
        .init(title: "Priority", freeValue: "—", proValue: "Yes", icon: "star.fill"),
    ]
}
