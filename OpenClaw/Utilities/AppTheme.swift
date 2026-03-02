import SwiftUI

@Observable
class AppTheme {
    static let shared = AppTheme()

    enum Style: String, CaseIterable {
        case soft
        case bold
    }

    var style: Style {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: "app_style") }
    }

    var purposes: Set<String> {
        didSet { UserDefaults.standard.set(Array(purposes), forKey: "app_purposes") }
    }

    var hasSelectedStyle: Bool {
        UserDefaults.standard.string(forKey: "app_style") != nil
    }

    var hasSeenTrialPaywall: Bool {
        get { UserDefaults.standard.bool(forKey: "seen_trial_paywall") }
        set { UserDefaults.standard.set(newValue, forKey: "seen_trial_paywall") }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: "app_style") ?? "bold"
        self.style = Style(rawValue: raw) ?? .bold
        let saved = UserDefaults.standard.stringArray(forKey: "app_purposes") ?? []
        self.purposes = Set(saved)
    }

    // MARK: - Accent

    var accent: Color {
        switch style {
        case .soft: Color(red: 0.76, green: 0.48, blue: 0.53)
        case .bold: .blue
        }
    }

    var accentGradient: [Color] {
        switch style {
        case .soft: [Color(red: 0.82, green: 0.52, blue: 0.56), Color(red: 0.92, green: 0.68, blue: 0.62)]
        case .bold: [.blue, .indigo]
        }
    }

    var secondaryAccent: Color {
        switch style {
        case .soft: Color(red: 0.92, green: 0.68, blue: 0.62)
        case .bold: .indigo
        }
    }

    var subtleAccentBackground: Color {
        switch style {
        case .soft: Color(red: 0.96, green: 0.91, blue: 0.90)
        case .bold: Color.blue.opacity(0.08)
        }
    }

    var buttonGradient: LinearGradient {
        LinearGradient(colors: accentGradient, startPoint: .leading, endPoint: .trailing)
    }
}
