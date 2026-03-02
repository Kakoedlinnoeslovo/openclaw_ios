import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SubscriptionService.self) private var subscription
    @Environment(AppTheme.self) private var theme

    @State private var showPaywall = false
    @State private var showUsage = false
    @State private var showClawHub = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    profileCard
                    subscriptionCard
                    aboutSection
                    signOutButton
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showUsage) {
                UsageView()
            }
            .sheet(isPresented: $showClawHub) {
                ClawHubView()
            }
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        VStack(spacing: 0) {
            if let user = auth.currentUser {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: theme.accentGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 52, height: 52)

                        Text(String(user.displayName.prefix(1)))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.displayName)
                            .font(.headline)
                        Text(user.email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    tierBadge
                }
                .padding(16)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var tierBadge: some View {
        Text(subscription.currentTier.rawValue.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                subscription.currentTier == .free
                    ? AnyShapeStyle(Color.gray)
                    : AnyShapeStyle(LinearGradient(colors: theme.accentGradient, startPoint: .leading, endPoint: .trailing))
            )
            .clipShape(Capsule())
    }

    // MARK: - Subscription Card

    private var subscriptionCard: some View {
        VStack(spacing: 0) {
            if subscription.currentTier == .free {
                Button { showPaywall = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20))
                            .foregroundStyle(.yellow)
                            .frame(width: 36, height: 36)
                            .background(.yellow.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Upgrade to Pro")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Unlock all models, agents, and skills")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.quaternary)
                    }
                    .padding(14)
                }

                Divider().padding(.leading, 62)
            }

            Button { showUsage = true } label: {
                settingsRow(
                    icon: "chart.bar.fill",
                    iconColor: theme.accent,
                    title: "Usage",
                    subtitle: "View tasks, tokens & limits"
                )
            }

            Divider().padding(.leading, 62)

            Button { Task { await subscription.restorePurchases() } } label: {
                settingsRow(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: theme.accent,
                    title: "Restore Purchases",
                    subtitle: nil
                )
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(spacing: 0) {
            Link(destination: URL(string: "https://openclaw.im")!) {
                settingsRow(
                    icon: "globe",
                    iconColor: .cyan,
                    title: "OpenClaw Website",
                    subtitle: nil
                )
            }

            Divider().padding(.leading, 62)

            Button { showClawHub = true } label: {
                settingsRow(
                    icon: "puzzlepiece.fill",
                    iconColor: .orange,
                    title: "ClawHub Skills",
                    subtitle: "Browse community skills"
                )
            }

            Divider().padding(.leading, 62)

            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.gray)
                    .frame(width: 36, height: 36)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text("Version")
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                Text("1.0.0")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Sign Out

    private var signOutButton: some View {
        Button(role: .destructive) {
            auth.signOut()
        } label: {
            HStack {
                Spacer()
                Text("Sign Out")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Helpers

    private func settingsRow(icon: String, iconColor: Color, title: String, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(14)
    }
}
