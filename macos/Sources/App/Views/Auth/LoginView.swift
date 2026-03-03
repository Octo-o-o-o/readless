import AppKit
import AuthenticationServices
import SwiftUI

// MARK: - Login View

struct LoginView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var code = ""
    @State private var isCodeSent = false
    @State private var isLoadingApple = false
    @State private var isLoadingEmail = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var animateIn = false

    // Strong reference prevents coordinator from being deallocated mid sign-in
    @State private var appleCoordinator: AppleSignInCoordinator?

    var body: some View {
        ZStack {
            // ── Background ───────────────────────────────────────────────
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            RadialGradient(
                colors: [Color.accentColor.opacity(0.08), .clear],
                center: .init(x: 0.5, y: 0.25),
                startRadius: 0,
                endRadius: 260
            )
            .ignoresSafeArea()

            // ── Card (centered by ZStack) ────────────────────────────────
            loginCard
                .offset(y: animateIn ? 0 : 20)
                .opacity(animateIn ? 1 : 0)
        }
        // Footer pinned to bottom
        .overlay(alignment: .bottom) {
            footerText
                .padding(.bottom, 20)
        }
        // Reliable window sizing via view-hierarchy access
        .background(LoginWindowSizer())
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                animateIn = true
            }
        }
    }

    // MARK: - Card

    private var loginCard: some View {
        VStack(spacing: 28) {
            brandingSection
            socialButtonsSection
            orDivider
            emailSection
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 40)
        .frame(maxWidth: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 40, y: 12)
        .padding(.horizontal, 40)
    }

    // MARK: - Branding

    private var brandingSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 66, height: 66)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 4)

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.primary)
            }

            VStack(spacing: 4) {
                Text("Welcome to Readless")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Text("Read less. Know more.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Social Buttons

    private var socialButtonsSection: some View {
        VStack(spacing: 10) {
            appleButton
            googleButton
        }
    }

    /// Sign in with Apple — always black background with white text.
    /// Never use Color.primary here: in dark mode it becomes white → white on white.
    private var appleButton: some View {
        Button(action: handleAppleSignIn) {
            HStack(spacing: 8) {
                if isLoadingApple {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 14, weight: .medium))
                }
                Text("Continue with Apple")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoadingApple || isLoadingEmail)
    }

    private var googleButton: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: {}) {
                HStack(spacing: 8) {
                    Text("G")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.26, green: 0.52, blue: 0.96),
                                    Color(red: 0.93, green: 0.26, blue: 0.21)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text("Continue with Google")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(true)
            .opacity(0.6)

            Text("Coming Soon")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.secondary, in: Capsule())
                .offset(x: 6, y: -8)
        }
    }

    // MARK: - Divider

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
            Text("or continue with email")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize()
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
    }

    // MARK: - Email Section

    private var emailSection: some View {
        VStack(spacing: 12) {
            // Status messages
            if let msg = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(msg).fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
                .transition(.push(from: .top).combined(with: .opacity))
            }

            if let msg = infoMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(msg)
                }
                .font(.caption)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
                .transition(.push(from: .top).combined(with: .opacity))
            }

            // Email field
            LGTextField(icon: "envelope", placeholder: "Email address", text: $email)
                .disabled(isCodeSent)
                .opacity(isCodeSent ? 0.6 : 1)
                .animation(.easeInOut(duration: 0.2), value: isCodeSent)

            // Code field (animated in after send)
            if isCodeSent {
                LGTextField(
                    icon: "shield.lefthalf.filled",
                    placeholder: "6-digit verification code",
                    text: $code
                )
                .transition(.push(from: .bottom).combined(with: .opacity))
            }

            // Primary action
            Button {
                Task { isCodeSent ? await verifyCode() : await sendCode() }
            } label: {
                HStack(spacing: 8) {
                    if isLoadingEmail {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: isCodeSent ? "checkmark.shield.fill" : "paperplane.fill")
                            .font(.system(size: 13))
                        Text(isCodeSent ? "Verify & Sign In" : "Send Verification Code")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.accentColor.opacity(primaryButtonDisabled ? 0.45 : 1))
                )
            }
            .buttonStyle(.plain)
            .disabled(primaryButtonDisabled)
            .animation(.easeInOut(duration: 0.15), value: primaryButtonDisabled)

            // Resend / change email
            if isCodeSent {
                HStack(spacing: 6) {
                    Button("Resend code") { Task { await sendCode() } }
                    Text("·").foregroundStyle(.tertiary)
                    Button("Change email") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isCodeSent = false
                            code = ""
                            infoMessage = nil
                            errorMessage = nil
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isCodeSent)
        .animation(.spring(response: 0.3), value: errorMessage)
        .animation(.spring(response: 0.3), value: infoMessage)
    }

    private var footerText: some View {
        Text("By continuing, you agree to our Terms of Service and Privacy Policy.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 60)
    }

    private var primaryButtonDisabled: Bool {
        isLoadingEmail || isLoadingApple || email.isEmpty || (isCodeSent && code.count != 6)
    }

    // MARK: - Actions

    private func handleAppleSignIn() {
        isLoadingApple = true
        errorMessage = nil

        let coordinator = AppleSignInCoordinator()
        appleCoordinator = coordinator

        coordinator.onSuccess = { token in
            Task { @MainActor in
                do {
                    try await self.authService.signInWithApple(identityToken: token)
                    self.dismiss()
                } catch {
                    withAnimation { self.errorMessage = error.localizedDescription }
                }
                self.isLoadingApple = false
                self.appleCoordinator = nil
            }
        }

        coordinator.onFailure = { error in
            Task { @MainActor in
                let nsError = error as NSError
                // ASAuthorizationError.canceled = 1001, ignore it
                if nsError.code != ASAuthorizationError.canceled.rawValue {
                    withAnimation { self.errorMessage = error.localizedDescription }
                }
                self.isLoadingApple = false
                self.appleCoordinator = nil
            }
        }

        coordinator.performSignIn()
    }

    private func sendCode() async {
        isLoadingEmail = true
        errorMessage = nil
        infoMessage = nil

        do {
            try await authService.sendLoginCode(email: email)
            withAnimation(.spring(response: 0.35)) { isCodeSent = true }
            infoMessage = "Code sent to \(email)"
        } catch {
            withAnimation { errorMessage = error.localizedDescription }
        }

        isLoadingEmail = false
    }

    private func verifyCode() async {
        isLoadingEmail = true
        errorMessage = nil
        infoMessage = nil

        do {
            try await authService.loginWithCode(email: email, code: code)
            dismiss()
        } catch {
            withAnimation { errorMessage = error.localizedDescription }
        }

        isLoadingEmail = false
    }
}

// MARK: - Glass Text Field

struct LGTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        )
    }
}

// MARK: - Window Sizer
//
// Uses viewDidMoveToWindow (reliable) instead of NSApp.keyWindow (unreliable at launch)
// to resize the login window. Also skips sheets so it doesn't resize the parent window
// when LoginView is presented modally (e.g., from Settings).

private struct LoginWindowSizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { SizerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class SizerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Don't resize sheet windows (when LoginView is shown as a sheet)
            guard let window, !window.isSheet else { return }
            DispatchQueue.main.async { [weak window] in
                guard let window else { return }
                window.setContentSize(NSSize(width: 540, height: 680))
                window.center()
            }
        }
    }
}

// MARK: - Apple Sign In Coordinator
//
// Uses ASAuthorizationController directly with explicit presentationAnchor.
// The SwiftUI SignInWithAppleButton wrapper doesn't reliably set this on macOS
// with .hiddenTitleBar windows, causing ASAuthorizationError.unknown (code 1000).

final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    var onSuccess: ((String) -> Void)?
    var onFailure: ((Error) -> Void)?

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first ?? NSWindow()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let token = String(data: tokenData, encoding: .utf8)
        else {
            let err = NSError(
                domain: "com.readless.auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to read Apple identity token."]
            )
            onFailure?(err)
            return
        }
        onSuccess?(token)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        onFailure?(error)
    }

    func performSignIn() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.email, .fullName]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
}
