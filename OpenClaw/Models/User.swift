import Foundation

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let displayName: String
    let avatarURL: String?
    let tier: SubscriptionTier
    let createdAt: Date

    enum SubscriptionTier: String, Codable {
        case free
        case pro
        case team
    }
}

struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

struct AuthResponse: Codable {
    let user: User
    let tokens: AuthTokens
}

struct UsageStats: Codable {
    let tasksToday: Int
    let tasksLimit: Int
    let tokensUsed: Int
    let tokensLimit: Int
    let agentCount: Int
    let agentLimit: Int
    let skillCount: Int
    let skillLimit: Int
}
