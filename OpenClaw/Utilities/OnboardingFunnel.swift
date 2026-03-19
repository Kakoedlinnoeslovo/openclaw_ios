import Foundation

enum OnboardingFunnel {
    static let completeKey = "onboarding.funnel_complete"

    static var isComplete: Bool {
        get { UserDefaults.standard.bool(forKey: completeKey) }
        set { UserDefaults.standard.set(newValue, forKey: completeKey) }
    }

    static func resetForNewAccount() {
        UserDefaults.standard.set(false, forKey: completeKey)
        UserDefaults.standard.set(false, forKey: "seen_trial_paywall")
    }
}
