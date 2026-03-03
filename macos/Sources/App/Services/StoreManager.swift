import Foundation
import StoreKit
import Networking

// MARK: - Subscription Error

enum SubscriptionError: LocalizedError {
    case productFetchFailed
    case productNotFound(String)
    case purchaseCancelled
    case purchaseFailed(Error)
    case receiptVerificationFailed(Error)
    case transactionNotFound
    case invalidTransaction
    case userNotAuthenticated

    var errorDescription: String? {
        switch self {
        case .productFetchFailed:
            return "Failed to fetch products from App Store"
        case .productNotFound(let id):
            return "Product not found: \(id)"
        case .purchaseCancelled:
            return "Purchase was cancelled"
        case .purchaseFailed(let error):
            return "Purchase failed: \(error.localizedDescription)"
        case .receiptVerificationFailed(let error):
            return "Receipt verification failed: \(error.localizedDescription)"
        case .transactionNotFound:
            return "Transaction not found"
        case .invalidTransaction:
            return "Invalid transaction"
        case .userNotAuthenticated:
            return "User must be authenticated to purchase"
        }
    }
}

// MARK: - Store Manager

/// StoreKit 2 service for managing App Store in-app purchases and subscriptions
///
/// Features:
/// - Product fetching from App Store
/// - Purchase flow with backend receipt verification
/// - Transaction monitoring and auto-renewal
/// - Restore purchases
///
/// Product IDs:
/// - Basic Monthly: com.readless.basic.monthly ($4.99/month, 7-day trial)
/// - Pro Monthly: com.readless.pro.monthly ($9.99/month, 7-day trial)
@MainActor
@Observable
final class StoreManager {
    static let shared = StoreManager()

    // MARK: - Product IDs

    private static let productIDs = [
        "com.readless.basic.monthly",
        "com.readless.pro.monthly"
    ]

    // MARK: - Published State

    /// All available products fetched from App Store
    private(set) var products: [Product] = []

    /// Set of product IDs the user has purchased (active subscriptions)
    private(set) var purchasedProductIDs: Set<String> = []

    /// Whether a purchase operation is in progress
    private(set) var isPurchasing = false

    /// Last error that occurred
    private(set) var lastError: SubscriptionError?

    // MARK: - Private State

    /// Background task listening to transaction updates
    @ObservationIgnored
    private var transactionListener: Task<Void, Never>?

    // MARK: - Initialization

    private init() {
        print("[StoreManager] Initializing...")
        startTransactionListener()
    }

    nonisolated deinit {
        transactionListener?.cancel()
    }

    // MARK: - Product Loading

    /// Load products from App Store
    ///
    /// Fetches the two subscription products defined in Product IDs.
    /// Updates the `products` array with fetched products.
    ///
    /// - Throws: SubscriptionError.productFetchFailed if loading fails
    func loadProducts() async throws {
        print("[StoreManager] Loading products...")

        do {
            // StoreKit 2 API: fetch products by IDs
            let fetchedProducts = try await Product.products(for: Self.productIDs)

            guard !fetchedProducts.isEmpty else {
                print("[StoreManager] ❌ No products found")
                throw SubscriptionError.productFetchFailed
            }

            self.products = fetchedProducts
            print("[StoreManager] ✅ Loaded \(fetchedProducts.count) products")

            // Log product details
            for product in fetchedProducts {
                print("[StoreManager] Product: \(product.id) - \(product.displayName) - \(product.displayPrice)")
            }

            // Load current entitlements
            await updatePurchasedProducts()
        } catch {
            print("[StoreManager] ❌ Failed to load products: \(error)")
            lastError = .productFetchFailed
            throw SubscriptionError.productFetchFailed
        }
    }

    // MARK: - Purchase Flow

    /// Purchase a subscription product
    ///
    /// Flow:
    /// 1. Check user authentication
    /// 2. Execute StoreKit purchase
    /// 3. Extract transaction JWS receipt
    /// 4. Verify receipt with backend
    /// 5. Refresh user info from backend
    /// 6. Update purchased products
    ///
    /// - Parameter product: The product to purchase
    /// - Throws: SubscriptionError for various failure cases
    func purchase(_ product: Product) async throws {
        print("[StoreManager] Starting purchase for: \(product.id)")

        // Check authentication
        guard AuthService.shared.isAuthenticated else {
            print("[StoreManager] ❌ User not authenticated")
            lastError = .userNotAuthenticated
            throw SubscriptionError.userNotAuthenticated
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            // StoreKit 2 API: execute purchase
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                // Extract transaction from verification result
                let transaction = try checkVerified(verification)

                print("[StoreManager] ✅ Purchase successful, transaction ID: \(transaction.id)")

                // Verify receipt with backend (pass verification result for JWS)
                try await verifyReceipt(verificationResult: verification)

                // Finish the transaction
                await transaction.finish()

                // Update purchased products
                await updatePurchasedProducts()

                // Refresh user info to get updated subscription tier
                try? await AuthService.shared.refreshAccessToken()

                print("[StoreManager] ✅ Purchase completed and verified")

            case .userCancelled:
                print("[StoreManager] ⚠️ Purchase cancelled by user")
                lastError = .purchaseCancelled
                throw SubscriptionError.purchaseCancelled

            case .pending:
                print("[StoreManager] ⏳ Purchase pending (Ask to Buy)")
                // Transaction will be handled by transaction listener when approved
                break

            @unknown default:
                print("[StoreManager] ❌ Unknown purchase result")
                throw SubscriptionError.purchaseFailed(NSError(domain: "StoreManager", code: -1))
            }
        } catch let error as SubscriptionError {
            print("[StoreManager] ❌ Purchase error: \(error)")
            lastError = error
            throw error
        } catch {
            print("[StoreManager] ❌ Purchase failed: \(error)")
            let subscriptionError = SubscriptionError.purchaseFailed(error)
            lastError = subscriptionError
            throw subscriptionError
        }
    }

    // MARK: - Restore Purchases

    /// Restore previous purchases from Transaction.currentEntitlements
    ///
    /// Iterates through all active transactions and verifies them with backend.
    /// Used when user reinstalls app or logs in on new device.
    ///
    /// - Throws: SubscriptionError.receiptVerificationFailed if verification fails
    func restorePurchases() async throws {
        print("[StoreManager] Restoring purchases...")

        isPurchasing = true
        defer { isPurchasing = false }

        var hasActiveSubscription = false

        // StoreKit 2 API: iterate through current entitlements (active transactions)
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                print("[StoreManager] Found transaction: \(transaction.id) for product: \(transaction.productID)")

                // Verify with backend (pass verification result for JWS)
                try await verifyReceipt(verificationResult: result)

                hasActiveSubscription = true

            } catch {
                print("[StoreManager] ⚠️ Failed to restore transaction: \(error)")
                // Continue with other transactions even if one fails
                continue
            }
        }

        // Update purchased products
        await updatePurchasedProducts()

        // Refresh user info
        try? await AuthService.shared.refreshAccessToken()

        if hasActiveSubscription {
            print("[StoreManager] ✅ Restore completed - found active subscriptions")
        } else {
            print("[StoreManager] ⚠️ No active subscriptions found")
        }
    }

    // MARK: - Transaction Listener

    /// Start background listener for transaction updates
    ///
    /// Monitors Transaction.updates stream for:
    /// - New purchases (Ask to Buy approved)
    /// - Auto-renewals
    /// - Subscription changes
    ///
    /// Runs forever in background and auto-verifies with backend.
    private func startTransactionListener() {
        // Cancel existing listener
        transactionListener?.cancel()

        // StoreKit 2 API: listen to transaction updates stream
        transactionListener = Task {
            print("[StoreManager] Transaction listener started")

            for await result in Transaction.updates {
                await MainActor.run {
                    do {
                        let transaction = try StoreManager.shared.checkVerified(result)

                        print("[StoreManager] 🔔 Transaction update: \(transaction.id) for product: \(transaction.productID)")

                        // Verify with backend (pass verification result for JWS)
                        Task {
                            do {
                                try await StoreManager.shared.verifyReceipt(verificationResult: result)

                                // Finish the transaction
                                await transaction.finish()

                                // Update purchased products
                                await StoreManager.shared.updatePurchasedProducts()

                                // Refresh user info
                                try? await AuthService.shared.refreshAccessToken()

                                print("[StoreManager] ✅ Transaction update processed")

                            } catch {
                                print("[StoreManager] ❌ Failed to process transaction update: \(error)")
                            }
                        }

                    } catch {
                        print("[StoreManager] ❌ Failed to verify transaction: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Receipt Verification

    /// Verify transaction receipt with backend
    ///
    /// Sends the StoreKit JWS receipt to backend for server-side verification.
    /// Backend validates with Apple and updates user subscription record.
    ///
    /// - Parameter verificationResult: The verification result containing the transaction
    /// - Throws: SubscriptionError.receiptVerificationFailed if verification fails
    private func verifyReceipt(verificationResult: VerificationResult<Transaction>) async throws {
        // Extract transaction
        let transaction = try checkVerified(verificationResult)

        print("[StoreManager] Verifying receipt for transaction: \(transaction.id)")

        // Get JWS representation from verification result (StoreKit 2 signed receipt)
        let transactionJWS = verificationResult.jwsRepresentation

        do {
            // Call backend to verify receipt
            let response = try await APIClient.shared.verifyReceipt(
                transactionId: String(transaction.id),
                verificationData: transactionJWS,
                productId: transaction.productID
            )

            print("[StoreManager] ✅ Receipt verified - tier: \(response.subscriptionTier), expires: \(response.expiresAt)")

        } catch {
            print("[StoreManager] ❌ Receipt verification failed: \(error)")
            let subscriptionError = SubscriptionError.receiptVerificationFailed(error)
            lastError = subscriptionError
            throw subscriptionError
        }
    }

    // MARK: - Purchased Products

    /// Update set of purchased product IDs from current entitlements
    private func updatePurchasedProducts() async {
        var purchased = Set<String>()

        // StoreKit 2 API: iterate through current entitlements
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }

            // Check if transaction is active (not expired)
            if transaction.expirationDate == nil || transaction.expirationDate! > Date() {
                purchased.insert(transaction.productID)
            }
        }

        purchasedProductIDs = purchased
        print("[StoreManager] Updated purchased products: \(purchased)")
    }

    // MARK: - Verification Helper

    /// Check StoreKit verification result and extract transaction
    ///
    /// StoreKit 2 returns VerificationResult which can be:
    /// - .verified: Transaction is valid
    /// - .unverified: Transaction failed cryptographic verification
    ///
    /// - Parameter result: Verification result from StoreKit
    /// - Returns: Verified transaction
    /// - Throws: SubscriptionError.invalidTransaction if verification failed
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let error):
            print("[StoreManager] ❌ Transaction verification failed: \(error)")
            throw SubscriptionError.invalidTransaction
        }
    }

    // MARK: - Helpers

    /// Get product by ID
    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    /// Check if user has active subscription for product
    func isPurchased(_ productID: String) -> Bool {
        purchasedProductIDs.contains(productID)
    }

    /// Check if user has any active subscription
    var hasActiveSubscription: Bool {
        !purchasedProductIDs.isEmpty
    }
}
