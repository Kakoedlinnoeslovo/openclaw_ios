import SwiftUI

struct WelcomeView: View {
    @Environment(AppTheme.self) private var theme
    let onContinue: () -> Void

    @State private var appeared = false

    private let examples: [(label: String, emoji: String, message: String, isRight: Bool)] = [
        ("Social Media", "🎆", "Create trendy topics for Instagram", false),
        ("Relationships", "😍", "Give me three ideas of a perfect date", true),
        ("Summary", "📝", "Make my 3000 words essay shorter", false),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ForEach(Array(examples.enumerated()), id: \.offset) { index, example in
                    chatBubbleCard(
                        label: example.label,
                        emoji: example.emoji,
                        message: example.message,
                        alignRight: example.isRight
                    )
                    .offset(y: appeared ? 0 : 40)
                    .opacity(appeared ? 1 : 0)
                    .animation(
                        .spring(response: 0.7, dampingFraction: 0.8).delay(Double(index) * 0.15),
                        value: appeared
                    )
                }
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 4) {
                Text("Find Answers to")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: theme.accentGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text("Your Questions")
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
                .accessibilityIdentifier("onboarding_continue_1")

                onboardingPageIndicator(current: 0, total: 4, accent: theme.accent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .onAppear { appeared = true }
    }

    private func chatBubbleCard(label: String, emoji: String, message: String, alignRight: Bool) -> some View {
        HStack {
            if alignRight { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(emoji)
                        .font(.system(size: 14))
                    Text(label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        colors: theme.accentGradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())

                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.white.opacity(0.15), lineWidth: 0.5)
                    )
            }

            if !alignRight { Spacer(minLength: 40) }
        }
    }
}

func onboardingPageIndicator(current: Int, total: Int, accent: Color = .primary) -> some View {
    HStack(spacing: 8) {
        ForEach(0..<total, id: \.self) { i in
            Capsule()
                .fill(i == current ? accent : Color.gray.opacity(0.25))
                .frame(width: i == current ? 20 : 8, height: 8)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current)
        }
    }
    .padding(.top, 8)
}
