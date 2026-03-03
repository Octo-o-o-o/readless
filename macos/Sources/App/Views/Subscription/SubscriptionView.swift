import SwiftUI
import StoreKit
import Core
import Networking

/// Main subscription management view
///
/// Features:
/// - Displays current subscription status
/// - Shows available products with pricing
/// - Handles purchase flow
/// - Restores previous purchases
struct SubscriptionView: View {
    @State private var storeManager = StoreManager.shared
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccessMessage = false
    @State private var successMessage = ""
    @State private var successMessageTask: Task<Void, Never>?

    // Static cached formatter for better performance
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Subscription")
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    // Current status banner
                    if let user = authService.currentUser {
                        currentStatusBanner(user: user)
                    }

                    // Error message
                    if let errorMessage {
                        errorBanner(message: errorMessage)
                    }

                    // Success message
                    if showSuccessMessage {
                        successBanner(message: successMessage)
                    }

                    // Product cards
                    if isLoading {
                        ProgressView("Loading products...")
                            .padding(40)
                    } else if storeManager.products.isEmpty {
                        emptyStateView
                    } else {
                        productCardsView
                    }

                    // Restore purchases button
                    restorePurchasesButton

                    // Legal disclaimer
                    legalDisclaimer
                }
                .padding(24)
            }
        }
        .frame(width: 600, height: 700)
        .task {
            await loadProducts()
        }
    }

    // MARK: - Subviews

    private func currentStatusBanner(user: User) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: statusIcon(for: user.subscriptionTier))
                    .foregroundStyle(.blue)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Plan: \(user.subscriptionTier.displayName)")
                        .font(.headline)

                    if let expiresAt = user.subscriptionExpiresAt {
                        Text("Expires: \(formattedDate(expiresAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let trialExpiresAt = user.trialExpiresAt, user.subscriptionTier == .trial {
                        Text("Trial ends: \(formattedDate(trialExpiresAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(16)
            .background(statusColor(for: user.subscriptionTier).opacity(0.1))
            .cornerRadius(12)
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(message)
                .font(.body)
                .foregroundStyle(.red)

            Spacer()

            Button {
                errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }

    private func successBanner(message: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text(message)
                .font(.body)
                .foregroundStyle(.green)

            Spacer()

            Button {
                showSuccessMessage = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }

    private var productCardsView: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(sortedProducts, id: \.id) { product in
                ProductCard(
                    product: product,
                    isCurrentPlan: isCurrentPlan(product),
                    isPurchasing: storeManager.isPurchasing
                ) {
                    await purchaseProduct(product)
                }
            }
        }
    }

    private var restorePurchasesButton: some View {
        Button {
            Task {
                await restorePurchases()
            }
        } label: {
            HStack {
                if storeManager.isPurchasing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Restoring...")
                } else {
                    Image(systemName: "arrow.clockwise")
                    Text("Restore Purchases")
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
        .disabled(storeManager.isPurchasing)
        .padding(.top, 8)
    }

    private var legalDisclaimer: some View {
        VStack(spacing: 8) {
            Text("Subscriptions auto-renew unless cancelled. Cancel anytime in App Store settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Prices shown in your local currency. Subscriptions managed through App Store.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No products available")
                .font(.headline)

            Text("Unable to load subscription products from App Store. Please try again later.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task {
                    await loadProducts()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }

    // MARK: - Actions

    private func loadProducts() async {
        isLoading = true
        errorMessage = nil

        do {
            try await storeManager.loadProducts()
        } catch {
            errorMessage = "Could not load subscription products. Please check your connection and try again."
        }

        isLoading = false
    }

    private func purchaseProduct(_ product: Product) async {
        clearMessages()

        do {
            try await storeManager.purchase(product)
            showTemporarySuccess("Successfully subscribed to \(product.displayName)!")
        } catch SubscriptionError.purchaseCancelled {
            return
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: "Purchase failed. Please try again or contact support if this continues.")
        }
    }

    private func restorePurchases() async {
        clearMessages()

        do {
            try await storeManager.restorePurchases()

            if storeManager.hasActiveSubscription {
                showTemporarySuccess("Purchases restored successfully!")
            } else {
                errorMessage = "No active subscriptions found to restore"
            }
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: "Could not restore purchases. Please try again later.")
        }
    }

    private func clearMessages() {
        errorMessage = nil
        showSuccessMessage = false
        successMessageTask?.cancel()
    }

    private func showTemporarySuccess(_ message: String) {
        successMessageTask?.cancel()
        successMessage = message
        showSuccessMessage = true
        successMessageTask = Task {
            try? await Task.sleep(for: .seconds(3))
            showSuccessMessage = false
        }
    }

    private func userFacingMessage(for error: Error, fallback: String) -> String {
        if let apiError = error as? APIError {
            return apiError.localizedDescription
        }
        if error is URLError {
            return "Could not connect. Please check your internet connection."
        }
        return fallback
    }

    // MARK: - Helpers

    private var sortedProducts: [Product] {
        // Sort products: Basic first, then Pro
        storeManager.products.sorted { lhs, rhs in
            if lhs.id.contains("basic") { return true }
            if rhs.id.contains("basic") { return false }
            return lhs.id < rhs.id
        }
    }

    private func isCurrentPlan(_ product: Product) -> Bool {
        guard let user = authService.currentUser else { return false }

        // Check if product matches user's current tier
        if product.id.contains("basic") && user.subscriptionTier == .basic {
            return true
        }
        if product.id.contains("pro") && user.subscriptionTier == .pro {
            return true
        }
        return false
    }

    private func statusIcon(for tier: SubscriptionTier) -> String {
        switch tier {
        case .trial:
            return "clock"
        case .basic, .pro:
            return "checkmark.seal.fill"
        case .expired:
            return "exclamationmark.triangle"
        }
    }

    private func statusColor(for tier: SubscriptionTier) -> Color {
        switch tier {
        case .trial:
            return .blue
        case .basic, .pro:
            return .green
        case .expired:
            return .red
        }
    }

    private func formattedDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    SubscriptionView()
        .environment(AuthService.shared)
}
