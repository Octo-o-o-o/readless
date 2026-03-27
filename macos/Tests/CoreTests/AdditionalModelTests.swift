import XCTest
import Core

final class AdditionalModelTests: XCTestCase {
    func testSearchModePresentationMetadata() {
        XCTAssertEqual(SearchMode.cloud.displayName, "Cloud Search")
        XCTAssertEqual(SearchMode.cloud.icon, "cloud.fill")
        XCTAssertTrue(SearchMode.cloud.description.contains("semantic"))

        XCTAssertEqual(SearchMode.local.displayName, "Local Search")
        XCTAssertEqual(SearchMode.local.icon, "internaldrive.fill")
        XCTAssertTrue(SearchMode.local.description.contains("offline"))
    }

    func testUserTagCodableRoundTrip() throws {
        let original = UserTag(
            id: 7,
            tagName: "AI",
            contentCount: 3,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserTag.self, from: data)

        XCTAssertEqual(decoded.id, 7)
        XCTAssertEqual(decoded.tagName, "AI")
        XCTAssertEqual(decoded.contentCount, 3)
        XCTAssertEqual(decoded.createdAt, original.createdAt)
    }

    func testUserCodableRoundTripAndSubscriptionDisplayNames() throws {
        let original = User(
            id: UUID(uuidString: "12345678-1234-1234-1234-1234567890ab")!,
            email: "user@example.com",
            subscriptionTier: .pro,
            trialExpiresAt: nil,
            subscriptionExpiresAt: Date(timeIntervalSince1970: 1_720_000_000),
            emailVerified: true,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(User.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.email, "user@example.com")
        XCTAssertEqual(decoded.subscriptionTier, .pro)
        XCTAssertTrue(decoded.emailVerified)
        XCTAssertEqual(SubscriptionTier.trial.displayName, "Trial")
        XCTAssertEqual(SubscriptionTier.basic.displayName, "Basic")
        XCTAssertEqual(SubscriptionTier.pro.displayName, "Pro")
        XCTAssertEqual(SubscriptionTier.expired.displayName, "Expired")
    }
}
