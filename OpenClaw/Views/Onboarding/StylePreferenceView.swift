import SwiftUI

struct StylePreferenceView: View {
    @Environment(AppTheme.self) private var theme
    let onContinue: () -> Void

    @State private var appeared = false
    @State private var orbiting = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                agentVisual
            }
            .frame(height: 340)

            Spacer()

            VStack(spacing: 4) {
                Text("Explore Power of")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: theme.accentGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text("Smart AI-Agents")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
            }
            .padding(.bottom, 36)

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
                .accessibilityIdentifier("onboarding_continue_2")

                onboardingPageIndicator(current: 1, total: 4, accent: theme.accent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private var agentVisual: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [theme.accent.opacity(0.15), theme.accent.opacity(0.03), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 160
                    )
                )
                .frame(width: 320, height: 320)

            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(theme.accent.opacity(0.08 - Double(ring) * 0.02), lineWidth: 1)
                    .frame(width: CGFloat(140 + ring * 60), height: CGFloat(140 + ring * 60))
            }

            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(.ultraThinMaterial)
                    .frame(width: 200, height: 240)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(.white.opacity(0.15), lineWidth: 0.5)
                    )
                    .shadow(color: theme.accent.opacity(0.15), radius: 30, y: 10)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(
                                LinearGradient(colors: theme.accentGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text("AI Agent")
                            .font(.system(size: 15, weight: .bold))
                    }

                    ForEach(0..<3) { i in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(["Research", "Analysis", "Summary"][i])
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(.quaternarySystemFill))

                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(
                                            LinearGradient(
                                                colors: theme.accentGradient,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: appeared ? geo.size.width * [0.85, 0.65, 0.92][i] : 0)
                                        .animation(.easeOut(duration: 1.0).delay(0.5 + Double(i) * 0.2), value: appeared)
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
                .padding(20)
                .frame(width: 200, height: 240, alignment: .topLeading)
            }
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: appeared)

            floatingChip("wand.and.stars", "Analyze", offset: CGPoint(x: -85, y: -110), delay: 0.25)
            floatingChip("sparkles", "Generate", offset: CGPoint(x: 85, y: -80), delay: 0.35)
            floatingChip("doc.text", "Summarize", offset: CGPoint(x: -75, y: 100), delay: 0.45)
        }
        .onAppear {
            appeared = true
            orbiting = true
        }
    }

    private func floatingChip(_ icon: String, _ label: String, offset: CGPoint, delay: Double) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(colors: theme.accentGradient, startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(Capsule())
        .shadow(color: theme.accent.opacity(0.3), radius: 8, y: 3)
        .offset(x: offset.x, y: offset.y)
        .offset(y: appeared ? 0 : 20)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.7, dampingFraction: 0.75).delay(delay), value: appeared)
    }
}
