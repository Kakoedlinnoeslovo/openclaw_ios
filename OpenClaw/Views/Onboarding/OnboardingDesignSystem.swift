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

    /// Spiral dashes: neon blue → purple → magenta; `time` drives twinkle for a “live” field
    static func spiralDashColor(angle: Double, u: Double, pulse: Double, edgeFade: CGFloat, time: Double) -> Color {
        let t = max(0, min(1, 0.28 + u * 0.5 + 0.22 * sin(angle * 0.9)))
        let cyan = (0.0, 0.88, 1.0)
        let purple = (0.45, 0.25, 0.98)
        let magenta = (0.92, 0.22, 0.95)
        let r: Double
        let g: Double
        let b: Double
        if t < 0.5 {
            let s = t * 2
            r = cyan.0 + (purple.0 - cyan.0) * s
            g = cyan.1 + (purple.1 - cyan.1) * s
            b = cyan.2 + (purple.2 - cyan.2) * s
        } else {
            let s = (t - 0.5) * 2
            r = purple.0 + (magenta.0 - purple.0) * s
            g = purple.1 + (magenta.1 - purple.1) * s
            b = purple.2 + (magenta.2 - purple.2) * s
        }
        let twinkle = 0.78 + 0.22 * sin(angle * 2.35 + time * 2.15)
        let baseOpacity = (0.24 + u * 0.42) * pulse * Double(edgeFade) * twinkle
        return Color(red: r, green: g, blue: b).opacity(min(1, baseOpacity))
    }

    /// Selected onboarding chip: soft tint under labels
    static var chipSelectedFill: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.22, blue: 0.42).opacity(0.55),
                Color(red: 0.22, green: 0.12, blue: 0.38).opacity(0.45),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var chipStrokeGradient: LinearGradient {
        LinearGradient(
            colors: [gradientBlue, iosBlue, gradientMagenta],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 45, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let rotation = reduceMotion ? 0 : t * 0.14
            let pulse = reduceMotion ? 1.0 : 0.84 + 0.16 * sin(t * 0.72)
            Canvas { context, size in
                let center = focal.spiralCenter(in: size)
                let maxR = hypot(size.width, size.height) * 0.66
                let count = 780
                for i in 0..<count {
                    let u = Double(i) / Double(count)
                    let angle = rotation + u * 17 * .pi
                    let r = u * maxR
                    let x = center.x + CGFloat(cos(angle)) * CGFloat(r)
                    let y = center.y + CGFloat(sin(angle)) * CGFloat(r)
                    let dist = hypot(x - center.x, y - center.y)
                    let edgeFade = max(0.16, min(1, 1.12 - Double(dist / max(1, maxR * 0.94))))
                    let len: CGFloat = u < 0.3 ? 7.5 : (u < 0.62 ? 5.8 : 4.6)
                    let h: CGFloat = u < 0.38 ? 1.28 : 1.05
                    let dash = Path(CGRect(x: -len / 2, y: -h / 2, width: len, height: h))
                    let color = OnboardingPalette.spiralDashColor(
                        angle: angle,
                        u: u,
                        pulse: pulse,
                        edgeFade: CGFloat(edgeFade),
                        time: t
                    )
                    var c = context
                    c.translateBy(x: x, y: y)
                    c.rotate(by: Angle(radians: angle + 1.12))
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
