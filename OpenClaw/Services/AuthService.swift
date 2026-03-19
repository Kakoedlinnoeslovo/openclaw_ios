import Foundation
import AuthenticationServices

@Observable
final class AuthService {
    static let shared = AuthService()

    var currentUser: User?
    var isAuthenticated: Bool { currentUser != nil }
    var isLoading = false

    private init() {
        loadCachedUser()
        #if DEBUG
        applyUITestBootstrapIfNeeded()
        #endif
    }

    #if DEBUG
    private func applyUITestBootstrapIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        OnboardingFunnel.isComplete = true
        UserDefaults.standard.set(true, forKey: "seen_trial_paywall")
        currentUser = User(
            id: "00000000-0000-0000-0000-000000000001",
            email: "uitest@openclaw.test",
            displayName: "UI Test",
            avatarURL: nil,
            tier: .free,
            createdAt: Date()
        )
    }
    #endif

    func signUp(email: String, password: String, displayName: String) async throws {
        isLoading = true
        defer { isLoading = false }

        struct SignUpBody: Codable {
            let email: String
            let password: String
            let displayName: String
        }

        let response: AuthResponse = try await APIClient.shared.post(
            "/auth/register",
            body: SignUpBody(email: email, password: password, displayName: displayName)
        )
        saveTokens(response.tokens)
        currentUser = response.user
        cacheUser(response.user)
    }

    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        struct SignInBody: Codable {
            let email: String
            let password: String
        }

        let response: AuthResponse = try await APIClient.shared.post(
            "/auth/login",
            body: SignInBody(email: email, password: password)
        )
        saveTokens(response.tokens)
        currentUser = response.user
        cacheUser(response.user)
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential, preferredDisplayName: String? = nil) async throws {
        isLoading = true
        defer { isLoading = false }

        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw APIError.unknown
        }

        struct AppleSignInBody: Codable {
            let identityToken: String
            let fullName: String?
        }

        let fromApple = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmedPreferred = preferredDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let mergedName: String? = {
            if !fromApple.isEmpty { return fromApple }
            if !trimmedPreferred.isEmpty { return trimmedPreferred }
            return nil
        }()

        let response: AuthResponse = try await APIClient.shared.post(
            "/auth/apple",
            body: AppleSignInBody(
                identityToken: identityToken,
                fullName: mergedName
            )
        )
        saveTokens(response.tokens)
        currentUser = response.user
        cacheUser(response.user)
    }

    func signOut() {
        currentUser = nil
        Keychain.deleteValue(forKey: AppConstants.accessTokenKey)
        Keychain.deleteValue(forKey: AppConstants.refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: "cached_user")
    }

    func deleteAccount() async throws {
        isLoading = true
        defer { isLoading = false }
        try await APIClient.shared.delete("/auth/account")
        OnboardingFunnel.resetForNewAccount()
        signOut()
    }

    func refreshToken() async throws {
        guard let refreshToken = Keychain.loadString(forKey: AppConstants.refreshTokenKey) else {
            throw APIError.unauthorized
        }

        struct RefreshBody: Codable { let refreshToken: String }

        let tokens: AuthTokens = try await APIClient.shared.post(
            "/auth/refresh",
            body: RefreshBody(refreshToken: refreshToken)
        )
        saveTokens(tokens)
    }

    private func saveTokens(_ tokens: AuthTokens) {
        Keychain.saveString(tokens.accessToken, forKey: AppConstants.accessTokenKey)
        Keychain.saveString(tokens.refreshToken, forKey: AppConstants.refreshTokenKey)
    }

    private func cacheUser(_ user: User) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: "cached_user")
        }
    }

    private func loadCachedUser() {
        guard let data = UserDefaults.standard.data(forKey: "cached_user"),
              let user = try? JSONDecoder().decode(User.self, from: data),
              Keychain.loadString(forKey: AppConstants.accessTokenKey) != nil else {
            return
        }
        currentUser = user
    }
}
