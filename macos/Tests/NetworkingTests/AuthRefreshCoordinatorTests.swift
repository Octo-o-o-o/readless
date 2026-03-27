import XCTest
@testable import Networking

final class AuthRefreshCoordinatorTests: XCTestCase {
    func testRefreshTokenIfNeededWaitsForCompletionNotification() async {
        let center = NotificationCenter()
        let coordinator = AuthRefreshCoordinator(
            notificationCenter: center,
            timeout: .seconds(1)
        )

        var refreshRequests = 0
        let observer = center.addObserver(
            forName: .refreshAuthToken,
            object: nil,
            queue: nil
        ) { _ in
            refreshRequests += 1
            center.post(
                name: .authTokenRefreshCompleted,
                object: nil,
                userInfo: ["success": true]
            )
        }
        defer { center.removeObserver(observer) }

        let refreshed = await coordinator.refreshTokenIfNeeded()

        XCTAssertTrue(refreshed)
        XCTAssertEqual(refreshRequests, 1)
    }

    func testConcurrentRefreshCallsShareSingleInflightTask() async {
        let center = NotificationCenter()
        let coordinator = AuthRefreshCoordinator(
            notificationCenter: center,
            timeout: .seconds(1)
        )

        var refreshRequests = 0
        let observer = center.addObserver(
            forName: .refreshAuthToken,
            object: nil,
            queue: nil
        ) { _ in
            refreshRequests += 1
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                center.post(
                    name: .authTokenRefreshCompleted,
                    object: nil,
                    userInfo: ["success": true]
                )
            }
        }
        defer { center.removeObserver(observer) }

        async let first = coordinator.refreshTokenIfNeeded()
        async let second = coordinator.refreshTokenIfNeeded()
        let results = await [first, second]

        XCTAssertEqual(results, [true, true])
        XCTAssertEqual(refreshRequests, 1)
    }

    func testRefreshTokenIfNeededReturnsFalseOnTimeout() async {
        let center = NotificationCenter()
        let coordinator = AuthRefreshCoordinator(
            notificationCenter: center,
            timeout: .milliseconds(50)
        )

        let refreshed = await coordinator.refreshTokenIfNeeded()

        XCTAssertFalse(refreshed)
    }
}
