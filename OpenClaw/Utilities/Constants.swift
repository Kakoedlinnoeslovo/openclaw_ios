import Foundation

enum AppConstants {
    #if DEBUG
    static let apiBaseURL = "https://openclow.ngrok-free.app"
    static let wsBaseURL = "wss://openclow.ngrok-free.app/ws"
    #else
    static let apiBaseURL = "https://api.your-openclaw-server.com"
    static let wsBaseURL = "wss://api.your-openclaw-server.com/ws"
    #endif

    static let appStoreID = "6743122046"
    static let keychainService = "com.openclaw.app"
    static let accessTokenKey = "access_token"
    static let refreshTokenKey = "refresh_token"

    enum Subscription {
        static let proMonthlyID = "com.openclaw.pro.monthly"
        static let proYearlyID = "com.openclaw.pro.yearly"
        static let teamMonthlyID = "com.openclaw.team.monthly"
    }

    enum Features {
        static let signInWithAppleEnabled = false
    }

    enum Limits {
        static let freeAgents = 1
        static let freeDailyTasks = 10
        static let freeSkills = 5
        static let proAgents = 5
        static let proDailyTasks = 100
    }
}
