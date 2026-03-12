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
            await MainActor.run {
                notificationCenter.post(name: .refreshAuthToken, object: nil)
            }
            return await Self.waitForRefreshResult(
                notificationCenter: notificationCenter,
                timeout: timeout
            )
        }

        activeRefreshTask = refreshTask
        let refreshed = await refreshTask.value
        activeRefreshTask = nil
        return refreshed
    }

    private static func waitForRefreshResult(
        notificationCenter: NotificationCenter,
        timeout: Duration
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await notification in notificationCenter.notifications(
                    named: .authTokenRefreshCompleted
                ) {
                    return notification.userInfo?["success"] as? Bool ?? false
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
