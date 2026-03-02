import Foundation

// MARK: - Subscription Request/Response Models

public struct VerifyReceiptRequest: Codable {
    let transactionId: String
    let verificationData: String
    let productId: String

    enum CodingKeys: String, CodingKey {
        case transactionId = "transaction_id"
        case verificationData = "verification_data"
        case productId = "product_id"
    }
}

public struct VerifyReceiptResponse: Codable {
    public let subscriptionTier: String
    public let expiresAt: Date
    public let isTrial: Bool
    public let productId: String

    enum CodingKeys: String, CodingKey {
        case subscriptionTier = "subscription_tier"
        case expiresAt = "expires_at"
        case isTrial = "is_trial"
        case productId = "product_id"
    }
}

public struct SubscriptionStatusResponse: Codable {
    public let currentTier: String
    public let isTrial: Bool
    public let trialExpiresAt: Date?
    public let subscriptionExpiresAt: Date?
    public let productId: String?
    public let autoRenewEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case currentTier = "current_tier"
        case isTrial = "is_trial"
        case trialExpiresAt = "trial_expires_at"
        case subscriptionExpiresAt = "subscription_expires_at"
        case productId = "product_id"
        case autoRenewEnabled = "auto_renew_enabled"
    }
}

// MARK: - API Client Subscription Extension

extension APIClient {
    /// Verify App Store receipt and update backend subscription
    public func verifyReceipt(
        transactionId: String,
        verificationData: String,
        productId: String
    ) async throws -> VerifyReceiptResponse {
        let req = VerifyReceiptRequest(
            transactionId: transactionId,
            verificationData: verificationData,
            productId: productId
        )
        let payload = try JSONEncoder().encode(req)
        let data = try await request("/api/v1/subscription/verify-receipt", method: "POST", body: payload)
        return try JSONDecoder.apiDecoder.decode(VerifyReceiptResponse.self, from: data)
    }

    /// Get current subscription status
    public func getSubscriptionStatus() async throws -> SubscriptionStatusResponse {
        let data = try await request("/api/v1/subscription/status")
        return try JSONDecoder.apiDecoder.decode(SubscriptionStatusResponse.self, from: data)
    }
}
