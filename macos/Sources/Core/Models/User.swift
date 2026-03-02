import Foundation

/// User model matching backend schema
public struct User: Codable, Sendable {
    public let id: UUID
    public let email: String?
    public let subscriptionTier: SubscriptionTier
    public let trialExpiresAt: Date?
    public let subscriptionExpiresAt: Date?
    public let emailVerified: Bool
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case subscriptionTier = "subscription_tier"
        case trialExpiresAt = "trial_expires_at"
        case subscriptionExpiresAt = "subscription_expires_at"
        case emailVerified = "email_verified"
        case createdAt = "created_at"
    }

    public init(
        id: UUID,
        email: String?,
        subscriptionTier: SubscriptionTier,
        trialExpiresAt: Date?,
        subscriptionExpiresAt: Date?,
        emailVerified: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.email = email
        self.subscriptionTier = subscriptionTier
        self.trialExpiresAt = trialExpiresAt
        self.subscriptionExpiresAt = subscriptionExpiresAt
        self.emailVerified = emailVerified
        self.createdAt = createdAt
    }
}

/// Subscription tier enum matching backend
public enum SubscriptionTier: String, Codable, Sendable {
    case trial
    case basic
    case pro
    case expired
}
