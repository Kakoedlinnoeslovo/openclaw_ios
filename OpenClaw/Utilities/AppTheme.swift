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
        case .soft: Color(red: 0.85, green: 0.42, blue: 0.52)
        case .bold: Color(red: 0.30, green: 0.45, blue: 1.0)
        }
    }

    var accentGradient: [Color] {
        switch style {
        case .soft: [Color(red: 0.90, green: 0.40, blue: 0.55), Color(red: 0.95, green: 0.60, blue: 0.50)]
        case .bold: [Color(red: 0.30, green: 0.45, blue: 1.0), Color(red: 0.50, green: 0.30, blue: 0.95)]
        }
    }

    var secondaryAccent: Color {
        switch style {
        case .soft: Color(red: 0.95, green: 0.60, blue: 0.50)
        case .bold: Color(red: 0.50, green: 0.30, blue: 0.95)
        }
    }

    var subtleAccentBackground: Color {
        switch style {
        case .soft: Color(red: 0.96, green: 0.91, blue: 0.90)
        case .bold: Color(red: 0.30, green: 0.45, blue: 1.0).opacity(0.08)
        }
    }

    var buttonGradient: LinearGradient {
        LinearGradient(colors: accentGradient, startPoint: .leading, endPoint: .trailing)
    }

    var heroGradient: [Color] {
        switch style {
        case .soft: [Color(red: 0.90, green: 0.40, blue: 0.55), Color(red: 0.80, green: 0.35, blue: 0.70)]
        case .bold: [Color(red: 0.25, green: 0.50, blue: 1.0), Color(red: 0.45, green: 0.20, blue: 1.0)]
        }
    }

    var surfaceTint: Color {
        accent.opacity(0.06)
    }

    var cardBackground: Color {
        Color(.secondarySystemGroupedBackground)
    }

    var glassBackground: some ShapeStyle {
        .ultraThinMaterial
    }
}
