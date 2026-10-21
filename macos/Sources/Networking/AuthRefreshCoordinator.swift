import Foundation

public actor AuthRefreshCoordinator {
    private let notificationCenter: NotificationCenter
    private let timeout: Duration
    private var activeRefreshTask: Task<Bool, Never>?

    public init(
        notificationCenter: NotificationCenter = .default,
        timeout: Duration = .seconds(5)
    ) {
        self.notificationCenter = notificationCenter
        self.timeout = timeout
    }

    public func refreshTokenIfNeeded() async -> Bool {
        if let activeRefreshTask {
            return await activeRefreshTask.value
        }

        let refreshTask = Task<Bool, Never> { [notificationCenter, timeout] in
            let refreshResults = Self.makeRefreshResultStream(
                notificationCenter: notificationCenter
            )
            await MainActor.run {
                notificationCenter.post(name: .refreshAuthToken, object: nil)
            }
            return await Self.waitForRefreshResult(
                refreshResults: refreshResults,
                timeout: timeout
            )
        }

        activeRefreshTask = refreshTask
        let refreshed = await refreshTask.value
        activeRefreshTask = nil
        return refreshed
    }

    private static func makeRefreshResultStream(
        notificationCenter: NotificationCenter,
    ) -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let observer = notificationCenter.addObserver(
                forName: .authTokenRefreshCompleted,
                object: nil,
                queue: nil
            ) { notification in
                continuation.yield(notification.userInfo?["success"] as? Bool ?? false)
                continuation.finish()
            }

            continuation.onTermination = { _ in
                notificationCenter.removeObserver(observer)
            }
        }
    }

    private static func waitForRefreshResult(
        refreshResults: AsyncStream<Bool>,
        timeout: Duration
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await success in refreshResults {
                    return success
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}
