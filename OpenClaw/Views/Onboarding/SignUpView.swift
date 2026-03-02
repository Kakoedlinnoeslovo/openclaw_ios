import SwiftUI
import AuthenticationServices

struct SignUpView: View{
    
    @Environment(AuthService.self) private var auth
    
    @State private var email = "ro.degtiarev@gmail.com"
    @State private var password = "1234567"
    @State private var displayName = "Roman"
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
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                dividerRow

                if !isSignIn {
                    TextField("Name", text: $displayName)
                        .textContentType(.name)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                SecureField("Password", text: $password)
                    .textContentType(isSignIn ? .password : .newPassword)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    performAuth()
                } label: {
                    if auth.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    } else {
                        Text(isSignIn ? "Sign In" : "Create Account")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(auth.isLoading || email.isEmpty || password.isEmpty)
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                withAnimation { isSignIn.toggle() }
            } label: {
                Text(isSignIn ? "Don't have an account? **Sign Up**" : "Already have an account? **Sign In**")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 32)
        }
    }

    private var dividerRow: some View {
        HStack {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
            Text("or")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
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
