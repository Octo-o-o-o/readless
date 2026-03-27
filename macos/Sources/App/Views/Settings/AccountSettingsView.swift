import SwiftUI
import Core

// MARK: - Account Settings

struct AccountSettingsView: View {
    @Environment(AuthService.self) private var authService
    @State private var showAuthSheet = false
    @State private var showSubscriptionSheet = false

    var body: some View {
        Form {
            Section("Account") {
                if let user = authService.currentUser {
                    // Logged in state
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Signed In")
                                .font(.headline)
                            if let email = user.email {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)

                    Button(action: {
                        Task {
                            try? await authService.signOut()
                        }
                    }) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    // Logged out state
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Not signed in")
                            .font(.headline)
                        Text("Sign in to sync your content across devices")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: {
                            showAuthSheet = true
                        }) {
                            Label("Sign In", systemImage: "person.crop.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                }
            }

            Section("Subscription") {
                if let user = authService.currentUser {
                    // Show current subscription status
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Plan")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(user.subscriptionTier.displayName)
                                .font(.headline)
                        }

                        Spacer()

                        Button("Manage Subscription") {
                            showSubscriptionSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Text("Sign in to manage your subscription")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("Your authentication is managed securely with JWT tokens. Refresh tokens are encrypted and stored securely in your device's Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .sheet(isPresented: $showAuthSheet) {
            LoginView()
        }
        .sheet(isPresented: $showSubscriptionSheet) {
            SubscriptionView()
        }
    }
}
