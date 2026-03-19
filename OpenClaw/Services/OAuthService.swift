import AuthenticationServices
import Foundation

enum OAuthProvider: String, CaseIterable {
    case slack
    case google
    case notion

    var displayName: String {
        switch self {
        case .slack: return "Slack"
        case .google: return "Google"
        case .notion: return "Notion"
        }
    }

    var iconName: String {
        switch self {
        case .slack: return "number.circle.fill"
        case .google: return "globe.americas.fill"
        case .notion: return "doc.on.doc.fill"
        }
    }

    var accentColorName: String {
        switch self {
        case .slack: return "slack"
        case .google: return "google"
        case .notion: return "notion"
        }
    }

    static func provider(forSkillId skillId: String) -> OAuthProvider? {
        let id = skillId.lowercased()
        if id.contains("slack") { return .slack }
        if id.contains("gog") || id.contains("google") || id.contains("calendar") || id.contains("gmail") { return .google }
        if id.contains("notion") { return .notion }
        return nil
    }
}

struct OAuthStatus: Codable {
    let connected: Bool
    let provider: String?
    let hasOauth: Bool
    let scope: String?
    let expiresAt: String?
    let connectedAt: String?
    let needsRefresh: Bool?
}

struct GlobalOAuthStatus: Codable {
    let connected: Bool
    let hasEligibleSkills: Bool
    let connectedCount: Int
    let totalCount: Int
    let needsRefresh: Bool?
}

@Observable
final class OAuthService {
    static let shared = OAuthService()

    /// Shown when the server reports OAuth admin credentials are missing (no in-app setup flow).
    static let connectionUnavailableInAppMessage = "Account connection isn’t available in the app right now."

    var isAuthenticating = false
    var lastError: String?

    private init() {}

    func startOAuthFlow(
        provider: OAuthProvider,
        agentId: String,
        skillId: String
    ) async throws -> Bool {
        isAuthenticating = true
        lastError = nil
        defer { isAuthenticating = false }

        let authURLResponse: AuthURLResponse
        do {
            authURLResponse = try await APIClient.shared.get(
                "/oauth/\(provider.rawValue)/authorize?agent_id=\(agentId)&skill_id=\(skillId)"
            )
        } catch let error as APIError {
            if case .clientError(_, let msg) = error, msg == "oauth_not_configured" {
                throw OAuthError.notConfigured
            }
            throw error
        }

        guard let authURL = URL(string: authURLResponse.authUrl) else {
            lastError = "Invalid authorization URL"
            throw OAuthError.invalidURL
        }

        let callbackURL = try await performWebAuth(url: authURL)

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            lastError = "Invalid callback"
            throw OAuthError.invalidCallback
        }

        if components.host == "oauth" {
            let pathParts = components.path.split(separator: "/")
            if let first = pathParts.first, first == "error" {
                let errorMsg = components.queryItems?.first(where: { $0.name == "error" })?.value ?? "Unknown error"
                lastError = errorMsg
                throw OAuthError.providerError(errorMsg)
            }
        }

        return true
    }

    func connectAll(
        provider: OAuthProvider,
        agents: [Agent]
    ) async throws -> Bool {
        guard let (agentId, skillId) = Self.firstEligibleSkill(provider: provider, agents: agents) else {
            throw OAuthError.notConfigured
        }

        isAuthenticating = true
        lastError = nil
        defer { isAuthenticating = false }

        let authURLResponse: AuthURLResponse
        do {
            authURLResponse = try await APIClient.shared.get(
                "/oauth/\(provider.rawValue)/authorize?agent_id=\(agentId)&skill_id=\(skillId)&connect_all=true"
            )
        } catch let error as APIError {
            if case .clientError(_, let msg) = error, msg == "oauth_not_configured" {
                throw OAuthError.notConfigured
            }
            throw error
        }

        guard let authURL = URL(string: authURLResponse.authUrl) else {
            lastError = "Invalid authorization URL"
            throw OAuthError.invalidURL
        }

        let callbackURL = try await performWebAuth(url: authURL)

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            lastError = "Invalid callback"
            throw OAuthError.invalidCallback
        }

        if components.host == "oauth" {
            let pathParts = components.path.split(separator: "/")
            if let first = pathParts.first, first == "error" {
                let errorMsg = components.queryItems?.first(where: { $0.name == "error" })?.value ?? "Unknown error"
                lastError = errorMsg
                throw OAuthError.providerError(errorMsg)
            }
        }

        return true
    }

    func checkGlobalStatus(provider: OAuthProvider) async throws -> GlobalOAuthStatus {
        try await APIClient.shared.get(
            "/oauth/\(provider.rawValue)/status-global"
        )
    }

    func checkStatus(agentId: String, skillId: String) async throws -> OAuthStatus {
        try await APIClient.shared.get(
            "/oauth/status?agent_id=\(agentId)&skill_id=\(skillId)"
        )
    }

    static func firstEligibleSkill(provider: OAuthProvider, agents: [Agent]) -> (agentId: String, skillId: String)? {
        for agent in agents {
            for skill in agent.skills {
                if OAuthProvider.provider(forSkillId: skill.skillId) == provider {
                    return (agent.id, skill.skillId)
                }
            }
        }
        return nil
    }

    static func hasEligibleSkills(provider: OAuthProvider, agents: [Agent]) -> Bool {
        firstEligibleSkill(provider: provider, agents: agents) != nil
    }

    @MainActor
    private func performWebAuth(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "openclaw"
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: OAuthError.sessionError(error))
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: OAuthError.noCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }

            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = OAuthPresentationContext.shared
            session.start()
        }
    }
}

enum OAuthError: LocalizedError {
    case invalidURL
    case invalidCallback
    case providerError(String)
    case sessionError(Error)
    case noCallback
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid authorization URL"
        case .invalidCallback: return "Invalid callback from service"
        case .providerError(let msg): return "Authorization failed: \(msg)"
        case .sessionError(let err): return err.localizedDescription
        case .noCallback: return "No response from service"
        case .notConfigured: return "OAuth not configured for this service"
        }
    }
}

private struct AuthURLResponse: Codable {
    let authUrl: String
    let state: String
}

final class OAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first
        else {
            return ASPresentationAnchor()
        }
        return window
    }
}
