import SwiftUI
import UserNotifications

struct NotificationPromptView: View {
    @Environment(AppTheme.self) private var theme
    let onComplete: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {}

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(theme.accent.opacity(0.15))
                        .frame(width: 80, height: 80)

                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(theme.accent)
                        .symbolEffect(.bounce, value: appeared)
                }

                VStack(spacing: 8) {
                    Text("Enable Notifications")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    Text("Get notified when your AI agents complete tasks and deliver results.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                VStack(spacing: 10) {
                    Button {
                        requestNotifications()
                    } label: {
                        Text("Allow Notifications")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(theme.buttonGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityIdentifier("notification_allow")

                    Button {
                        onComplete()
                    } label: {
                        Text("Maybe Later")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .accessibilityIdentifier("notification_skip")
                }
            }
            .padding(28)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.15), radius: 30, y: 10)
            .padding(.horizontal, 36)
            .scaleEffect(appeared ? 1 : 0.8)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: appeared)
        }
        .onAppear { appeared = true }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
            DispatchQueue.main.async {
                onComplete()
            }
        }
    }
}
