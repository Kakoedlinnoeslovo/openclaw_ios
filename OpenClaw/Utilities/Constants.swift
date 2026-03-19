import Foundation

enum AppConstants {
    static let apiBaseURL = "https://64.23.222.65.nip.io"
    static let wsBaseURL = "wss://64.23.222.65.nip.io/ws"

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
