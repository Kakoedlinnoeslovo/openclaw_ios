import SwiftUI

extension View {
    /// Soft tint over the system grouped background for home and settings roots.
    func homeSettingsScreenBackground(theme: AppTheme) -> some View {
        background {
            ZStack {
                Color(.systemGroupedBackground)
                LinearGradient(
                    colors: [
                        theme.accent.opacity(0.06),
                        (theme.heroGradient.first ?? theme.accent).opacity(0.04),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        }
    }

    /// Liquid Glass on iOS 26+; ultra-thin material + hairline stroke on earlier OS versions.
    @ViewBuilder
    func homeSettingsCard(cornerRadius: CGFloat = 16, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self.modifier(HomeSettingsMaterialCardModifier(cornerRadius: cornerRadius))
        }
    }
}

private struct HomeSettingsMaterialCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

/// Shared sampling region for home quick-action cards on iOS 26+.
struct HomeQuickActionsGlassShell<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}
