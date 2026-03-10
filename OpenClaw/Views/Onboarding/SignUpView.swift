import SwiftUI
import AuthenticationServices

struct SignUpView: View {
    
    @Environment(AuthService.self) private var auth
    @Environment(AppTheme.self) private var theme
    
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isSignIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text(isSignIn ? "Welcome back" : "Create account")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                Text(isSignIn ? "Sign in to continue" : "Start building AI agents")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 40)

            VStack(spacing: 16) {
                if AppConstants.Features.signInWithAppleEnabled {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    dividerRow
                }

                if !isSignIn {
                    styledTextField(
                        icon: "person",
                        placeholder: "Name",
                        text: $displayName,
                        contentType: .name,
                        keyboardType: .default
                    )
                }

                styledTextField(
                    icon: "envelope",
                    placeholder: "Email",
                    text: $email,
                    contentType: .emailAddress,
                    keyboardType: .emailAddress
                )

                styledSecureField(
                    icon: "lock",
                    placeholder: "Password",
                    text: $password
                )

                if let errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                        Text(errorMessage)
                            .font(.caption)
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }

                Button {
                    performAuth()
                } label: {
                    if auth.isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                    } else {
                        Text(isSignIn ? "Sign In" : "Create Account")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                    }
                }
                .foregroundStyle(.white)
                .background(theme.buttonGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: theme.accent.opacity(0.25), radius: 10, y: 5)
                .disabled(auth.isLoading || email.isEmpty || password.isEmpty)
                .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1.0)
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.25)) { isSignIn.toggle() }
            } label: {
                Text(isSignIn ? "Don't have an account? **Sign Up**" : "Already have an account? **Sign In**")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 32)
        }
    }

    private func styledTextField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        contentType: UITextContentType,
        keyboardType: UIKeyboardType
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.tertiary)
                .frame(width: 20)

            TextField(placeholder, text: text)
                .textContentType(contentType)
                .keyboardType(keyboardType)
                .autocapitalization(.none)
                .textFieldStyle(.plain)
                .font(.subheadline)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
    }

    private func styledSecureField(
        icon: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.tertiary)
                .frame(width: 20)

            SecureField(placeholder, text: text)
                .textContentType(.password)
                .textFieldStyle(.plain)
                .font(.subheadline)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
    }

    private var dividerRow: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color(.separator).opacity(0.3))
                .frame(height: 0.5)
            Text("or")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Rectangle()
                .fill(Color(.separator).opacity(0.3))
                .frame(height: 0.5)
        }
    }

    private func performAuth() {
        Task {
            do {
                errorMessage = nil
                if isSignIn {
                    try await auth.signIn(email: email, password: password)
                } else {
                    try await auth.signUp(email: email, password: password, displayName: displayName)
                }
            } catch let error as APIError {
                errorMessage = error.errorDescription
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            Task {
                do {
                    errorMessage = nil
                    try await AuthService.shared.signInWithApple(credential: credential)
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
