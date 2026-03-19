import SwiftUI
import AuthenticationServices

// MARK: - Welcome

struct OnboardingWelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            VStack(alignment: .leading, spacing: 20) {
                Text("Get instant help\nfor daily tasks")
                    .font(OnboardingTypography.heroHeadline)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(OnboardingPalette.titleGradient)
                    .frame(maxWidth: .infinity, alignment: .leading)

                (
                    Text("OpenClaw is your all-in-one AI assistant. ")
                        .foregroundStyle(.white)
                    + Text("Powered by leading models.")
                        .foregroundStyle(OnboardingPalette.muted)
                )
                .font(OnboardingTypography.body)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 16) {
                OnboardingPrimaryButton(title: "Get started", action: onContinue, accessibilityId: "onboarding_continue_1")
                OnboardingLegalFooter()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
    }
}

// MARK: - Name

struct OnboardingNameStep: View {
    @Binding var name: String
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                OnboardingSkipButton(action: onSkip)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 12) {
                OnboardingGradientTitle(text: "Hey! I am OpenClaw AI. What’s your name?", fontSize: 32)
                Text("Let us ask you a few questions to tailor your experience to your needs.")
                    .font(OnboardingTypography.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            TextField("", text: $name, prompt: Text("Your name").foregroundStyle(OnboardingPalette.muted))
                .font(.system(size: 18, weight: .medium))
                .multilineTextAlignment(.center)
                .padding(.vertical, 20)
                .padding(.horizontal, 16)
                .background(OnboardingPalette.chipFill)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.top, 28)

            Spacer()

            OnboardingPrimaryButton(
                title: "Continue",
                action: onContinue,
                enabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                accessibilityId: "onboarding_continue_2"
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
    }
}

// MARK: - Chip selection

private struct OnboardingChipGrid<Title: View>: View {
    @ViewBuilder let title: () -> Title
    let subtitle: String
    let options: [String]
    @Binding var selection: Set<String>
    let hint: String
    let continueId: String
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                OnboardingSkipButton(action: onSkip)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            title()
                .padding(.horizontal, 24)
                .padding(.top, 16)

            Text(subtitle)
                .font(OnboardingTypography.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.top, 10)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 108), spacing: 10, alignment: .leading)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(options, id: \.self) { option in
                    chip(option)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(OnboardingPalette.titleGradient)
                    .rotationEffect(.degrees(-25))
                Text(hint)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .italic()
                    .foregroundStyle(OnboardingPalette.titleGradient)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Spacer()

            OnboardingPrimaryButton(
                title: "Continue",
                action: onContinue,
                enabled: !selection.isEmpty,
                accessibilityId: continueId
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
    }

    private func chip(_ title: String) -> some View {
        let on = selection.contains(title)
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                if on { selection.remove(title) } else { selection.insert(title) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(OnboardingTypography.chip)
                    .foregroundStyle(.white)

                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OnboardingPalette.chipStrokeGradient)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background {
                Capsule(style: .continuous)
                    .fill(on ? AnyShapeStyle(OnboardingPalette.chipSelectedFill) : AnyShapeStyle(OnboardingPalette.chipFill))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        on ? AnyShapeStyle(OnboardingPalette.chipStrokeGradient) : AnyShapeStyle(Color.white.opacity(0.1)),
                        lineWidth: on ? 1.5 : 1
                    )
            }
            .shadow(
                color: on ? OnboardingPalette.iosBlue.opacity(0.28) : .clear,
                radius: on ? 10 : 0,
                y: on ? 3 : 0
            )
            .scaleEffect(on ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
    }
}

// MARK: - Use cases

struct OnboardingUseCasesStep: View {
    @Binding var selection: Set<String>
    let onContinue: () -> Void
    let onSkip: () -> Void

    private let options = [
        "Work", "Study", "Social Media", "Art", "Communication", "Self-Development", "Other",
    ]

    var body: some View {
        OnboardingChipGrid(
            title: {
                OnboardingGradientTitle(text: "What are you going to use OpenClaw AI for?", fontSize: 30)
            },
            subtitle: "This helps us understand your needs to customize OpenClaw AI for you.",
            options: options,
            selection: $selection,
            hint: "Choose as many as you like",
            continueId: "onboarding_continue_3",
            onContinue: onContinue,
            onSkip: onSkip
        )
    }
}

// MARK: - Interests

struct OnboardingInterestsStep: View {
    @Binding var selection: Set<String>
    let onContinue: () -> Void
    let onSkip: () -> Void

    private let options = [
        "Text Generation", "Math Solver", "Translation", "Image Generation", "Coding", "Other",
    ]

    var body: some View {
        OnboardingChipGrid(
            title: {
                OnboardingGradientTitle(text: "What features interest you the most?", fontSize: 30)
            },
            subtitle: "Please let us know what features matter to you the most.",
            options: options,
            selection: $selection,
            hint: "Same here: choose as many as you like",
            continueId: "onboarding_continue_4",
            onContinue: onContinue,
            onSkip: onSkip
        )
    }
}

// MARK: - Loading / social proof

struct OnboardingLoadingSocialStep: View {
    let onContinue: () -> Void

    @State private var phase = 0
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { timeline in
                let breath = 0.92 + 0.08 * sin(timeline.date.timeIntervalSinceReferenceDate * 1.15)
                Text("Your personal AI assistant will be ready in just a moment…")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(OnboardingPalette.titleGradient)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .opacity((phase >= 0 ? 1 : 0) * breath)
                    .scaleEffect(phase >= 0 ? 1 : 0.92)
                    .animation(.spring(response: 0.55, dampingFraction: 0.82), value: phase)
            }

            Spacer()

            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    laurelWarm
                    VStack(spacing: 16) {
                        HStack(spacing: 6) {
                            ForEach(0..<5, id: \.self) { i in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white)
                                    .opacity(phase >= 2 ? 1 : 0)
                                    .scaleEffect(phase >= 2 ? 1 : 0.5)
                                    .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.05 * Double(i)), value: phase)
                            }
                        }

                        Text("10,000,000")
                            .font(OnboardingTypography.heroHeadline)
                            .foregroundStyle(.white)
                            .opacity(phase >= 3 ? 1 : 0)
                            .scaleEffect(pulse && phase >= 3 ? 1.03 : 1)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)

                        Text("Users worldwide")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(OnboardingPalette.muted)
                            .opacity(phase >= 3 ? 1 : 0)
                    }
                    laurelWarm.rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                }
                .opacity(phase >= 1 ? 1 : 0)
                .offset(y: phase >= 1 ? 0 : 12)
                .animation(.easeOut(duration: 0.45).delay(0.1), value: phase)

                featuredRow
                    .opacity(phase >= 1 ? 1 : 0)
                    .offset(y: phase >= 1 ? 0 : 12)
                    .animation(.easeOut(duration: 0.45).delay(0.18), value: phase)
            }
            .padding(.bottom, 24)

            OnboardingPrimaryButton(title: "Continue", action: onContinue, accessibilityId: "onboarding_continue_5")
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
        }
        .onAppear {
            pulse = true
            withAnimation(.easeOut(duration: 0.01)) { phase = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { phase = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { phase = 2 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { phase = 3 }
        }
    }

    private var featuredRow: some View {
        HStack(spacing: 12) {
            laurelCool
            VStack(spacing: 2) {
                Text("Featured on the")
                    .font(OnboardingTypography.caption)
                    .foregroundStyle(.white.opacity(0.75))
                Text("App Store")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
            }
            laurelCool.rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
    }

    private var laurelWarm: some View {
        Image(systemName: "laurel.leading")
            .font(.system(size: 36, weight: .regular))
            .foregroundStyle(OnboardingPalette.laurelSocialGold)
    }

    private var laurelCool: some View {
        Image(systemName: "laurel.leading")
            .font(.system(size: 36, weight: .regular))
            .foregroundStyle(OnboardingPalette.laurelFeaturedCool)
    }
}

// MARK: - All set (celebration)

struct OnboardingAllSetStep: View {
    let onContinue: () -> Void

    @State private var phase = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)

            OnboardingGradientTitle(
                text: "You're all set!",
                fontSize: 34,
                textAlignment: .center,
                frameAlignment: .center,
                gradient: OnboardingPalette.celebrationTitleGradient
            )
            .accessibilityIdentifier("onboarding_all_set_title")
            .padding(.horizontal, 28)
            .opacity(phase >= 0 ? 1 : 0)
            .offset(y: phase >= 0 ? 0 : 8)
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: phase)

            Spacer()

            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    allSetLaurel
                    VStack(alignment: .center, spacing: 10) {
                        Text("Featured on the")
                            .font(OnboardingTypography.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                        Text("App Store")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)

                        HStack(spacing: 5) {
                            ForEach(0..<5, id: \.self) { i in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.white)
                                    .opacity(phase >= 2 ? 1 : 0)
                                    .scaleEffect(phase >= 2 ? 1 : 0.5)
                                    .animation(.spring(response: 0.4, dampingFraction: 0.72).delay(0.05 * Double(i)), value: phase)
                            }
                        }

                        Text("Amazing!")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text("— OpenClaw users")
                            .font(OnboardingTypography.caption)
                            .foregroundStyle(OnboardingPalette.muted)
                            .multilineTextAlignment(.center)
                    }
                    allSetLaurel.rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                }
                .opacity(phase >= 1 ? 1 : 0)
                .offset(y: phase >= 1 ? 0 : 12)
                .animation(.easeOut(duration: 0.45).delay(0.12), value: phase)
            }
            .padding(.bottom, 28)

            OnboardingPrimaryButton(
                title: "Continue",
                action: onContinue,
                accessibilityId: "onboarding_continue_all_set"
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .onAppear {
            phase = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { phase = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { phase = 2 }
        }
    }

    private var allSetLaurel: some View {
        Image(systemName: "laurel.leading")
            .font(.system(size: 38, weight: .regular))
            .foregroundStyle(OnboardingPalette.laurelFeaturedCool)
    }
}

// MARK: - Sign in with Apple

struct OnboardingAppleSignInStep: View {
    @Environment(AuthService.self) private var auth
    let preferredDisplayName: String
    let onSuccess: () -> Void

    private enum EmailAuthMode: String, CaseIterable, Identifiable {
        case signIn
        case createAccount

        var id: String { rawValue }

        var title: String {
            switch self {
            case .signIn: return "Sign in"
            case .createAccount: return "Create account"
            }
        }
    }

    @State private var errorMessage: String?
    @State private var email = ""
    @State private var password = ""
    @State private var emailAuthMode: EmailAuthMode = .signIn
    @State private var isSubmittingEmail = false

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDisplayName: String {
        preferredDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmitEmail: Bool {
        !trimmedEmail.isEmpty && !password.isEmpty && !isSubmittingEmail
    }

    private var emailAuthSubtitle: String {
        switch emailAuthMode {
        case .signIn:
            return "Use Sign in with Apple, or your email and password below."
        case .createAccount:
            return "Use Sign in with Apple, or create an account with email and password below."
        }
    }

    private var emailPrimaryButtonTitle: String {
        switch emailAuthMode {
        case .signIn: return "Sign in with email"
        case .createAccount: return "Create account"
        }
    }

    private var gradientTitleText: String {
        switch emailAuthMode {
        case .signIn: return "Sign in"
        case .createAccount: return "Create account"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Color.clear.frame(height: 28)

                OnboardingGradientTitle(
                    text: gradientTitleText,
                    fontSize: 30,
                    textAlignment: .center,
                    frameAlignment: .center
                )
                Text(emailAuthSubtitle)
                    .font(OnboardingTypography.body)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Picker("Email account action", selection: $emailAuthMode) {
                    ForEach(EmailAuthMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("onboarding_email_auth_mode")

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 24)
                .accessibilityIdentifier("onboarding_continue_6")

                Text("We use your Apple ID email to create your account.")
                    .font(OnboardingTypography.caption)
                    .foregroundStyle(OnboardingPalette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                onboardingEmailPasswordDivider

                onboardingCredentialField(
                    prompt: "Email",
                    text: $email,
                    contentType: .emailAddress,
                    keyboardType: .emailAddress,
                    accessibilityId: "onboarding_sign_in_email"
                )

                onboardingCredentialField(
                    prompt: "Password",
                    text: $password,
                    isSecure: true,
                    contentType: .password,
                    keyboardType: .default,
                    accessibilityId: "onboarding_sign_in_password"
                )

                Button(action: performEmailAuth) {
                    ZStack {
                        Text(emailPrimaryButtonTitle)
                            .font(OnboardingTypography.cta)
                            .foregroundStyle(canSubmitEmail ? Color.white : OnboardingPalette.muted)
                            .opacity(isSubmittingEmail ? 0 : 1)
                        if isSubmittingEmail {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(canSubmitEmail ? OnboardingPalette.iosBlue : OnboardingPalette.chipFill)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmitEmail)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("onboarding_email_password_sign_in")

                Color.clear.frame(height: 20)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: emailAuthMode) { _, _ in
            errorMessage = nil
        }
    }

    private var onboardingEmailPasswordDivider: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(height: 0.5)
            Text("or")
                .font(OnboardingTypography.caption)
                .foregroundStyle(OnboardingPalette.muted)
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(height: 0.5)
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
    }

    private func onboardingCredentialField(
        prompt: String,
        text: Binding<String>,
        isSecure: Bool = false,
        contentType: UITextContentType,
        keyboardType: UIKeyboardType,
        accessibilityId: String
    ) -> some View {
        Group {
            if isSecure {
                SecureField("", text: text, prompt: Text(prompt).foregroundStyle(OnboardingPalette.muted))
                    .textContentType(contentType)
                    .textInputAutocapitalization(.never)
            } else {
                TextField("", text: text, prompt: Text(prompt).foregroundStyle(OnboardingPalette.muted))
                    .textContentType(contentType)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .background(OnboardingPalette.chipFill)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 24)
        .accessibilityIdentifier(accessibilityId)
    }

    private func performEmailAuth() {
        guard canSubmitEmail else { return }
        Task {
            isSubmittingEmail = true
            defer { isSubmittingEmail = false }
            do {
                errorMessage = nil
                switch emailAuthMode {
                case .signIn:
                    try await auth.signIn(email: trimmedEmail, password: password)
                case .createAccount:
                    try await auth.signUp(
                        email: trimmedEmail,
                        password: password,
                        displayName: trimmedDisplayName
                    )
                }
                onSuccess()
            } catch let error as APIError {
                errorMessage = error.errorDescription
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            Task {
                do {
                    errorMessage = nil
                    try await auth.signInWithApple(credential: credential, preferredDisplayName: preferredDisplayName)
                    onSuccess()
                } catch let error as APIError {
                    errorMessage = error.errorDescription
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
