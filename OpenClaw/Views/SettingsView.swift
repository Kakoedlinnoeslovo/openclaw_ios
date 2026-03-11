import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SubscriptionService.self) private var subscription
    @Environment(AppTheme.self) private var theme

    @State private var showPaywall = false
    @State private var showUsage = false
    @State private var showClawHub = false
    @State private var showGoogleConfig = false
    @State private var oauthConfig: OAuthConfigResponse?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    profileCard
                    connectionsSection
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
            .sheet(isPresented: $showGoogleConfig) {
                NavigationStack {
                    GoogleOAuthConfigView(isConfigured: oauthConfig?.providers["google"]?.configured == true) {
                        await refreshOAuthConfig()
                    }
                }
            }
            .task {
                await refreshOAuthConfig()
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
                                    colors: theme.heroGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                            .shadow(color: theme.accent.opacity(0.2), radius: 8, y: 3)

                        Text(String(user.displayName.prefix(1)))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName)
                            .font(.system(size: 17, weight: .semibold))
                        Text(user.email)
                            .font(.system(size: 13))
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
        HStack(spacing: 3) {
            if subscription.currentTier != .free {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 8))
            }
            Text(subscription.currentTier.rawValue.uppercased())
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            subscription.currentTier == .free
                ? AnyShapeStyle(Color.gray.opacity(0.6))
                : AnyShapeStyle(LinearGradient(colors: theme.accentGradient, startPoint: .leading, endPoint: .trailing))
        )
        .clipShape(Capsule())
    }

    // MARK: - Connections

    private var connectionsSection: some View {
        VStack(spacing: 0) {
            Button { showGoogleConfig = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.26, green: 0.52, blue: 0.96), Color(red: 0.18, green: 0.42, blue: 0.90)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Google")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Text("Gmail, Calendar & Drive")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if oauthConfig?.providers["google"]?.configured == true {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                            Text("Active")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.green)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.quaternary)
                }
                .padding(14)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func refreshOAuthConfig() async {
        oauthConfig = try? await OAuthService.shared.fetchOAuthConfig()
    }

    // MARK: - Subscription Card

    private var subscriptionCard: some View {
        VStack(spacing: 0) {
            if subscription.currentTier == .free {
                Button { showPaywall = true } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.8, blue: 0.3), Color(red: 1.0, green: 0.55, blue: 0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 36, height: 36)

                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                        }

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
                            .font(.system(size: 11, weight: .semibold))
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
            if let url = URL(string: "https://openclaw.im") {
                Link(destination: url) {
                    settingsRow(
                        icon: "globe",
                        iconColor: .cyan,
                        title: "OpenClaw Website",
                        subtitle: nil
                    )
                }
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
                    .font(.system(size: 17))
                    .foregroundStyle(.gray)
                    .frame(width: 36, height: 36)
                    .background(Color.gray.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text("Version")
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                Text("1.0.0")
                    .font(.system(size: 13, weight: .medium))
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
                .font(.system(size: 17))
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.10))
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(14)
    }
}

// MARK: - Google OAuth Config

struct GoogleOAuthConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTheme.self) private var theme

    let isConfigured: Bool
    let onSaved: () async -> Void

    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var isSaving = false
    @State private var savedSuccessfully = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerCard
                credentialsForm
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                saveButton
                helpSection
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Google Setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private var headerCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.26, green: 0.52, blue: 0.96), Color(red: 0.18, green: 0.42, blue: 0.90)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Text("Connect Google Services")
                .font(.system(size: 17, weight: .semibold))

            Text("Enter your Google Cloud OAuth credentials to enable Gmail, Calendar, and Drive access for your agents.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if isConfigured && !savedSuccessfully {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Already configured")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.green)
            }

            if savedSuccessfully {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Saved successfully")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.green)
            }
        }
    }

    private var credentialsForm: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Client ID")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("xxxx.apps.googleusercontent.com", text: $clientId)
                    .font(.system(size: 14))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(14)

            Divider().padding(.leading, 14)

            VStack(alignment: .leading, spacing: 6) {
                Text("Client Secret")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                SecureField("GOCSPX-...", text: $clientSecret)
                    .font(.system(size: 14))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(14)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Text(isConfigured ? "Update Credentials" : "Save Credentials")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: canSave
                        ? [Color(red: 0.26, green: 0.52, blue: 0.96), Color(red: 0.18, green: 0.42, blue: 0.90)]
                        : [Color.gray.opacity(0.3), Color.gray.opacity(0.3)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!canSave || isSaving)
    }

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How to get credentials")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                helpStep("1", "Go to Google Cloud Console")
                helpStep("2", "Create a project (or select existing)")
                helpStep("3", "Enable Gmail, Calendar & Drive APIs")
                helpStep("4", "Go to Credentials > Create OAuth Client ID")
                helpStep("5", "Choose \"Web application\" type")
                helpStep("6", "Copy the Client ID and Client Secret here")
            }

            if let url = URL(string: "https://console.cloud.google.com/apis/credentials") {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 12))
                        Text("Open Google Cloud Console")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func helpStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color(red: 0.26, green: 0.52, blue: 0.96).opacity(0.8))
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }

    private var canSave: Bool {
        !clientId.trimmingCharacters(in: .whitespaces).isEmpty &&
        !clientSecret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await OAuthService.shared.saveOAuthConfig(
                provider: .google,
                clientId: clientId.trimmingCharacters(in: .whitespaces),
                clientSecret: clientSecret.trimmingCharacters(in: .whitespaces)
            )
            savedSuccessfully = true
            await onSaved()
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}
