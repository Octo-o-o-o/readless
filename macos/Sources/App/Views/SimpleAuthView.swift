import SwiftUI
import ClerkKit
import AuthenticationServices

/// Authentication view for macOS with email, Google, and Apple sign-in
struct SimpleAuthView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    enum AuthMode {
        case signIn
        case signUp

        var title: String {
            switch self {
            case .signIn: return "Sign In"
            case .signUp: return "Create Account"
            }
        }

        var buttonText: String {
            switch self {
            case .signIn: return "Sign In"
            case .signUp: return "Sign Up"
            }
        }

        var toggleText: String {
            switch self {
            case .signIn: return "Don't have an account? Sign up"
            case .signUp: return "Already have an account? Sign in"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(mode.title)
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    // Logo and Title
                    VStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 56))
                            .foregroundStyle(.blue)

                        Text("Welcome to Readless")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(mode == .signIn ? "Sign in to access your content" : "Create an account to get started")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)

                    // OAuth Buttons
                    VStack(spacing: 12) {
                        // Apple Sign In
                        Button(action: signInWithApple) {
                            HStack {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 18))
                                Text("Continue with Apple")
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        // Google Sign In
                        Button(action: signInWithGoogle) {
                            HStack {
                                Image(systemName: "g.circle.fill")
                                    .font(.system(size: 18))
                                Text("Continue with Google")
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .frame(maxWidth: 340)
                    .disabled(isLoading)

                    // Divider
                    HStack {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(height: 1)
                        Text("or")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(height: 1)
                    }
                    .frame(maxWidth: 340)

                    // Email/Password Form
                    VStack(spacing: 12) {
                        TextField("Email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()
                            .textCase(.lowercase)

                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(mode == .signUp ? .newPassword : .password)

                        if mode == .signUp {
                            SecureField("Confirm Password", text: $confirmPassword)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.newPassword)
                        }
                    }
                    .frame(maxWidth: 340)
                    .disabled(isLoading)

                    // Error Message
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 340)
                    }

                    // Sign In/Up Button
                    Button(action: performEmailAuth) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(mode.buttonText)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: 340)
                    .frame(height: 44)
                    .disabled(!isFormValid || isLoading)

                    // Toggle Mode
                    Button(action: { toggleMode() }) {
                        Text(mode.toggleText)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)

                    // Privacy Notice
                    Text("By continuing, you agree to Readless's Terms of Service and Privacy Policy")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                        .padding(.bottom, 20)
                }
            }
        }
        .frame(width: 480, height: 680)
    }

    // MARK: - Computed Properties

    private var isFormValid: Bool {
        guard !email.isEmpty, !password.isEmpty else { return false }
        if mode == .signUp {
            return password == confirmPassword && password.count >= 8
        }
        return true
    }

    // MARK: - Actions

    private func toggleMode() {
        mode = mode == .signIn ? .signUp : .signIn
        errorMessage = nil
        password = ""
        confirmPassword = ""
    }

    private func performEmailAuth() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                if mode == .signIn {
                    try await signInWithEmail()
                } else {
                    try await signUpWithEmail()
                }

                // If successful, session should be created
                if clerk.session != nil {
                    do {
                        try await AuthManager.shared.refreshToken()
                        print("[SimpleAuthView] ✅ Token synced successfully after email auth")
                        await MainActor.run {
                            dismiss()
                        }
                    } catch {
                        print("[SimpleAuthView] ❌ Failed to sync token: \(error)")
                        await MainActor.run {
                            errorMessage = "Failed to sync authentication token"
                            isLoading = false
                        }
                    }
                } else {
                    await MainActor.run {
                        errorMessage = "Authentication succeeded but no session created"
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = parseError(error)
                    isLoading = false
                }
            }
        }
    }

    private func signInWithEmail() async throws {
        _ = try await clerk.auth.signInWithPassword(
            identifier: email,
            password: password
        )
    }

    private func signUpWithEmail() async throws {
        // Create sign-up with email and password
        _ = try await clerk.auth.signUp(
            emailAddress: email,
            password: password
        )

        // Note: Depending on Clerk configuration, email verification might be required
        // The user might need to verify their email before the session is created
    }

    private func signInWithGoogle() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                _ = try await clerk.auth.signInWithOAuth(provider: .google)

                if clerk.session != nil {
                    do {
                        try await AuthManager.shared.refreshToken()
                        print("[SimpleAuthView] ✅ Token synced successfully after Google auth")
                        await MainActor.run {
                            dismiss()
                        }
                    } catch {
                        print("[SimpleAuthView] ❌ Failed to sync token: \(error)")
                        await MainActor.run {
                            errorMessage = "Failed to sync authentication token"
                            isLoading = false
                        }
                    }
                } else {
                    await MainActor.run {
                        errorMessage = "Google sign-in cancelled or failed"
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = parseError(error)
                    isLoading = false
                }
            }
        }
    }

    private func signInWithApple() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                _ = try await clerk.auth.signInWithApple()

                if clerk.session != nil {
                    do {
                        try await AuthManager.shared.refreshToken()
                        print("[SimpleAuthView] ✅ Token synced successfully after Apple auth")
                        await MainActor.run {
                            dismiss()
                        }
                    } catch {
                        print("[SimpleAuthView] ❌ Failed to sync token: \(error)")
                        await MainActor.run {
                            errorMessage = "Failed to sync authentication token"
                            isLoading = false
                        }
                    }
                } else {
                    await MainActor.run {
                        errorMessage = "Apple sign-in cancelled or failed"
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = parseError(error)
                    isLoading = false
                }
            }
        }
    }

    private func parseError(_ error: Error) -> String {
        let errorString = error.localizedDescription

        // Clean up common error messages
        if errorString.contains("password") {
            return "Invalid email or password"
        } else if errorString.contains("exist") {
            return "An account with this email already exists"
        } else if errorString.contains("verification") {
            return "Please check your email for verification link"
        } else if errorString.contains("network") {
            return "Network error. Please check your connection"
        }

        return errorString
    }
}
