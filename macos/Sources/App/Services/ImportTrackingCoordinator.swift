import Foundation
import Core

@MainActor
final class ImportTrackingCoordinator {
    struct TrackingBehavior {
        var showResultOnReady: Bool
        var showFailureToast: Bool
        var keepsCapsule: Bool

        static let background = TrackingBehavior(
            showResultOnReady: false,
            showFailureToast: false,
            keepsCapsule: false
        )

        static let silentImport = TrackingBehavior(
            showResultOnReady: false,
            showFailureToast: true,
            keepsCapsule: false
        )

        static let displayImport = TrackingBehavior(
            showResultOnReady: true,
            showFailureToast: true,
            keepsCapsule: true
        )

        static let quietImport = TrackingBehavior(
            showResultOnReady: true,
            showFailureToast: true,
            keepsCapsule: false
        )

        func merged(with other: TrackingBehavior) -> TrackingBehavior {
            TrackingBehavior(
                showResultOnReady: showResultOnReady || other.showResultOnReady,
                showFailureToast: showFailureToast || other.showFailureToast,
                keepsCapsule: keepsCapsule || other.keepsCapsule
            )
        }
    }

    typealias FetchContentHandler = (String) async throws -> Content
    typealias PersistContentHandler = (Content) async -> Void
    typealias ContentUpdateHandler = (Content) -> Void
    typealias CompletionHandler = (Content, TrackingBehavior) -> Void
    typealias PollingErrorHandler = (String, Error) -> Void

    private let fetchContent: FetchContentHandler
    private let persistContent: PersistContentHandler
    private let onContentUpdate: ContentUpdateHandler
    private let onReady: CompletionHandler
    private let onFailure: CompletionHandler
    private let onPollingError: PollingErrorHandler
    private let pollingInterval: Duration

    private var tasks: [String: Task<Void, Never>] = [:]
    private var behaviors: [String: TrackingBehavior] = [:]

    init(
        pollingInterval: Duration = .seconds(2),
        fetchContent: @escaping FetchContentHandler,
        persistContent: @escaping PersistContentHandler,
        onContentUpdate: @escaping ContentUpdateHandler,
        onReady: @escaping CompletionHandler,
        onFailure: @escaping CompletionHandler,
        onPollingError: @escaping PollingErrorHandler = { _, _ in }
    ) {
        self.pollingInterval = pollingInterval
        self.fetchContent = fetchContent
        self.persistContent = persistContent
        self.onContentUpdate = onContentUpdate
        self.onReady = onReady
        self.onFailure = onFailure
        self.onPollingError = onPollingError
    }

    func trackIfNeeded(_ content: Content, behavior: TrackingBehavior) {
        guard content.status == .pending || content.status == .processing else {
            cancel(contentID: content.id)
            return
        }

        behaviors[content.id] = (behaviors[content.id] ?? .background).merged(with: behavior)

        guard tasks[content.id] == nil else {
            return
        }

        tasks[content.id] = Task { [weak self] in
            await self?.pollUntilFinished(contentID: content.id)
        }
    }

    func resumeBackgroundTracking(for contents: [Content]) {
        let activeIDs = Set(
            contents.filter { $0.status == .pending || $0.status == .processing }
                .map(\.id)
        )

        for content in contents where content.status == .pending || content.status == .processing {
            trackIfNeeded(content, behavior: .background)
        }

        for id in Array(tasks.keys) where !activeIDs.contains(id) {
            cancel(contentID: id)
        }
    }

    func disableInteractiveBehavior(contentID: String) {
        guard var behavior = behaviors[contentID] else {
            return
        }
        behavior.showResultOnReady = false
        behavior.keepsCapsule = false
        behaviors[contentID] = behavior
    }

    func cancel(contentID: String) {
        tasks[contentID]?.cancel()
        tasks[contentID] = nil
        behaviors[contentID] = nil
    }

    func cancelAll() {
        for contentID in Array(tasks.keys) {
            cancel(contentID: contentID)
        }
    }

    private func pollUntilFinished(contentID: String) async {
        defer {
            tasks[contentID] = nil
        }

        while !Task.isCancelled {
            do {
                let content = try await fetchContent(contentID)
                onContentUpdate(content)
                await persistContent(content)

                switch content.status {
                case .pending, .processing:
                    try? await Task.sleep(for: pollingInterval)
                case .ready:
                    let behavior = behaviors[contentID] ?? .background
                    behaviors[contentID] = nil
                    onReady(content, behavior)
                    return
                case .failed:
                    let behavior = behaviors[contentID] ?? .background
                    behaviors[contentID] = nil
                    onFailure(content, behavior)
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                onPollingError(contentID, error)
                try? await Task.sleep(for: pollingInterval)
            }
        }
    }
}
