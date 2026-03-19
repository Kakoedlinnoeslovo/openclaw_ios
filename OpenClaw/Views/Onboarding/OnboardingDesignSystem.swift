import SwiftUI

enum OnboardingPalette {
    static let background = Color.black

    /// System blue #007AFF
    static let iosBlue = Color(red: 0, green: 122 / 255, blue: 1)

    static let chipFill = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)

    /// Secondary label #8E8E93
    static let muted = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)

    static let skipPill = Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255)

    /// Headline gradient start (~#5E9AFF → ties to #007AFF)
    static let gradientBlue = Color(red: 94 / 255, green: 154 / 255, blue: 1)

    /// Headline / accent magenta #C04DF9
    static let gradientMagenta = Color(red: 192 / 255, green: 77 / 255, blue: 249 / 255)

    /// Strong pink for second line #FF47D6
    static let accentPink = Color(red: 1, green: 71 / 255, blue: 214 / 255)

    /// Alias for chip / laurel gradients
    static let gradientPurple = gradientMagenta

    static var titleGradient: LinearGradient {
        LinearGradient(
            colors: [gradientBlue, iosBlue, gradientMagenta],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// “You’re all set!” — periwinkle → magenta (reference success screen)
    static var celebrationTitleGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.72, green: 0.7, blue: 1),
                Color(red: 1, green: 0.38, blue: 0.78),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Laurel beside social proof / user count (warm gold → orange)
    static var laurelSocialGold: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1, green: 0.88, blue: 0.42),
                Color(red: 0.92, green: 0.48, blue: 0.14),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Laurel beside “Featured on the App Store” and testimonial (cyan → deep indigo)
    static var laurelFeaturedCool: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.25, green: 0.92, blue: 0.95),
                Color(red: 0.22, green: 0.18, blue: 0.52),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Spiral dashes: blend electric blue ↔ magenta by angle + radius; opacity scales with `pulse`
    static func spiralDashColor(angle: Double, u: Double, pulse: Double, edgeFade: CGFloat) -> Color {
        let t = max(0, min(1, 0.35 + u * 0.45 + 0.2 * sin(angle * 0.85)))
        let blue = (Double(94 / 255), Double(154 / 255), 1.0)
        let pink = (Double(192 / 255), Double(77 / 255), Double(249 / 255))
        let r = blue.0 + (pink.0 - blue.0) * t
        let g = blue.1 + (pink.1 - blue.1) * t
        let b = blue.2 + (pink.2 - blue.2) * t
        let baseOpacity = (0.09 + u * 0.26) * pulse * Double(edgeFade)
        return Color(red: r, green: g, blue: b).opacity(min(1, baseOpacity))
    }
}

/// Vortex focal point for the spiral dash field (welcome: upper; loading / centered screens: middle).
enum OnboardingSpiralFocal {
    case upper
    case center

    func spiralCenter(in size: CGSize) -> CGPoint {
        switch self {
        case .upper:
            CGPoint(x: size.width * 0.5, y: size.height * 0.28)
        case .center:
            CGPoint(x: size.width * 0.5, y: size.height * 0.46)
        }
    }
}

/// Shared onboarding / paywall typography (SF Pro–style system fonts, reference sizes).
enum OnboardingTypography {
    static let heroHeadline = Font.system(size: 34, weight: .bold)
    static let screenTitle = Font.system(size: 30, weight: .bold)
    static let callout = Font.system(size: 26, weight: .bold)
    static let body = Font.system(size: 17, weight: .regular)
    static let bodyMedium = Font.system(size: 17, weight: .medium)
    static let chip = Font.system(size: 15, weight: .semibold)
    static let hint = Font.system(size: 15, weight: .medium)
    static let caption = Font.system(size: 12, weight: .medium)
    static let cta = Font.system(size: 17, weight: .bold)
    static let paywallHeadline = Font.system(size: 28, weight: .bold)
    static let paywallFeature = Font.system(size: 17, weight: .semibold)
    static let planTitle = Font.system(size: 17, weight: .bold)
    static let planMeta = Font.system(size: 13, weight: .regular)
    static let planPrice = Font.system(size: 15, weight: .bold)
    static let planUnit = Font.system(size: 12, weight: .regular)
}

struct OnboardingSpiralBackground: View {
    var focal: OnboardingSpiralFocal = .upper

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 45, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let rotation = t * 0.09
            let pulse = 0.88 + 0.12 * sin(t * 0.7)
            Canvas { context, size in
                let center = focal.spiralCenter(in: size)
                let maxR = hypot(size.width, size.height) * 0.58
                let count = 480
                for i in 0..<count {
                    let u = Double(i) / Double(count)
                    let angle = rotation + u * 15 * .pi
                    let r = u * maxR
                    let x = center.x + CGFloat(cos(angle)) * CGFloat(r)
                    let y = center.y + CGFloat(sin(angle)) * CGFloat(r)
                    let dist = hypot(x - center.x, y - center.y)
                    let edgeFade = max(0.12, min(1, 1.08 - Double(dist / max(1, maxR * 0.96))))
                    let len: CGFloat = u < 0.35 ? 5.5 : 4.5
                    let dash = Path(CGRect(x: -len / 2, y: -0.5, width: len, height: 1.1))
                    let color = OnboardingPalette.spiralDashColor(angle: angle, u: u, pulse: pulse, edgeFade: CGFloat(edgeFade))
                    var c = context
                    c.translateBy(x: x, y: y)
                    c.rotate(by: Angle(radians: angle + 1.15))
                    c.fill(dash, with: .color(color))
                }
            }
            .allowsHitTesting(false)
        }
    }
}

struct OnboardingPrimaryButton: View {
    let title: String
    let action: () -> Void
    var enabled: Bool = true
    var accessibilityId: String?

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(OnboardingTypography.cta)
                .foregroundStyle(enabled ? Color.white : OnboardingPalette.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(enabled ? OnboardingPalette.iosBlue : OnboardingPalette.chipFill)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .modifier(OnboardingAccessIdModifier(id: accessibilityId))
    }
}

private struct OnboardingAccessIdModifier: ViewModifier {
    let id: String?

    func body(content: Content) -> some View {
        if let id, !id.isEmpty {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
    }
}

struct OnboardingSkipButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Skip")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.88))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(OnboardingPalette.skipPill)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding_skip")
    }
}

struct OnboardingGradientTitle: View {
    let text: String
    var fontSize: CGFloat = 34
    var textAlignment: TextAlignment = .leading
    var frameAlignment: Alignment = .leading
    var gradient: LinearGradient = OnboardingPalette.titleGradient

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .bold))
            .multilineTextAlignment(textAlignment)
            .foregroundStyle(gradient)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    /// Reference-style centered multiline headline (name step, etc.).
    static func centered(_ text: String, fontSize: CGFloat = 34) -> OnboardingGradientTitle {
        OnboardingGradientTitle(
            text: text,
            fontSize: fontSize,
            textAlignment: .center,
            frameAlignment: .center
        )
    }
}

struct OnboardingLegalFooter: View {
    var body: some View {
        Text(attributedLegal)
            .font(OnboardingTypography.caption)
            .multilineTextAlignment(.center)
            .tint(OnboardingPalette.muted)
            .foregroundStyle(OnboardingPalette.muted)
            .padding(.horizontal, 24)
    }

    private var attributedLegal: AttributedString {
        var s = AttributedString("By continuing, you accept our ")
        var t = AttributedString("Terms of Service")
        t.link = AppConstants.Legal.termsURL
        t.underlineStyle = .single
        s += t
        s += AttributedString(" and ")
        var p = AttributedString("Privacy Policy")
        p.link = AppConstants.Legal.privacyURL
        p.underlineStyle = .single
        s += p
        return s
    }
}
