import SwiftUI

struct PurposeSelectionView: View {
    @Environment(AppTheme.self) private var theme
    let onContinue: () -> Void

    @State private var appeared = false
    @State private var glowPulse = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [theme.accent.opacity(0.20), theme.accent.opacity(0.05), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 160
                        )
                    )
                    .frame(width: 320, height: 320)
                    .scaleEffect(glowPulse ? 1.08 : 1.0)
                    .animation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true), value: glowPulse)

                Circle()
                    .stroke(theme.accent.opacity(0.08), lineWidth: 1)
                    .frame(width: 200, height: 200)

                Circle()
                    .stroke(theme.accent.opacity(0.05), lineWidth: 1)
                    .frame(width: 280, height: 280)

                VStack(spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 26)
                            .fill(
                                LinearGradient(
                                    colors: theme.heroGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 96, height: 96)

                        Image(systemName: "cpu.fill")
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: theme.accent.opacity(0.35), radius: 24, y: 8)
                    .scaleEffect(appeared ? 1 : 0.5)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: appeared)

                    VStack(spacing: 8) {
                        Text("OpenClaw")
                            .font(.system(size: 36, weight: .bold, design: .rounded))

                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.accent)
                            Text("Powered by")
                                .foregroundStyle(.secondary)
                            Text("AI technology")
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: theme.accentGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        .font(.system(size: 15, weight: .medium))
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3), value: appeared)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    socialProofStat("50K+", subtitle: "Users")
                    socialProofStat("4.8", subtitle: "Rating", icon: "star.fill")
                    socialProofStat("1M+", subtitle: "Tasks Done")
                }
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.5), value: appeared)
            }
            .padding(.bottom, 32)

            VStack(spacing: 14) {
                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Text("Continue")
                            .font(.system(size: 17, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(theme.buttonGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: theme.accent.opacity(0.3), radius: 12, y: 6)
                }
                .accessibilityIdentifier("onboarding_continue_3")

                onboardingPageIndicator(current: 2, total: 4, accent: theme.accent)

                HStack(spacing: 4) {
                    Text("By proceeding, you accept our")
                    Link("Terms of Use", destination: URL(string: "https://openclaw.im/terms")!)
                        .foregroundStyle(theme.accent.opacity(0.7))
                    Text("and")
                    Link("Privacy Policy", destination: URL(string: "https://openclaw.im/privacy")!)
                        .foregroundStyle(theme.accent.opacity(0.7))
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .onAppear {
            appeared = true
            glowPulse = true
        }
    }

    private func socialProofStat(_ value: String, subtitle: String, icon: String? = nil) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(.yellow)
                }
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}
