import Foundation

enum AppConstants {
    static let apiBaseURL = "https://64.23.222.65.nip.io"
    static let wsBaseURL = "wss://64.23.222.65.nip.io/ws"

    static let appStoreID = "6743122046"
    static let keychainService = "im.openclaw.app"
    static let accessTokenKey = "access_token"
    static let refreshTokenKey = "refresh_token"

    /// App Store Connect: auto-renewable weekly + yearly in one subscription group; 3-day intro on weekly if desired. Prices: weekly $6.99, yearly $69.99.
    enum Subscription {
        static let proWeeklyID = "com.openclaw.pro.weekly"
        static let proYearlyID = "com.openclaw.pro.yearly"
    }

    enum Legal {
        static let termsURL = URL(string: "https://kakoedlinnoeslovo.github.io/openclaw_ios/terms.html")!
        static let privacyURL = URL(string: "https://kakoedlinnoeslovo.github.io/openclaw_ios/privacy.html")!
        static let supportURL = URL(string: "https://kakoedlinnoeslovo.github.io/openclaw_ios/support.html")!
    }

    enum Features {
        static let signInWithAppleEnabled = true
    }

    enum Limits {
        static let freeAgents = 1
        static let freeDailyTasks = 10
        static let freeSkills = 5
        static let proAgents = 5
        static let proDailyTasks = 100
    }
}
