import Foundation
import Core
import Networking

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

    typealias FetchStatusesHandler = ([String]) async throws -> [ContentStatusSnapshot]
    typealias FetchContentHandler = (String) async throws -> Content
    typealias PersistContentHandler = (Content) async -> Void
    typealias ContentUpdateHandler = (Content) -> Void
    typealias CompletionHandler = (Content, TrackingBehavior) -> Void
    typealias PollingErrorHandler = (String, Error) -> Void

    private let fetchStatuses: FetchStatusesHandler
    private let fetchContent: FetchContentHandler
    private let persistContent: PersistContentHandler
    private let onContentUpdate: ContentUpdateHandler
    private let onReady: CompletionHandler
    private let onFailure: CompletionHandler
    private let onPollingError: PollingErrorHandler
    private let pollingInterval: Duration

    private var behaviors: [String: TrackingBehavior] = [:]
    private var lastSnapshots: [String: ContentStatusSnapshot] = [:]
    private var pollingTask: Task<Void, Never>?

    init(
        pollingInterval: Duration = .seconds(2),
        fetchStatuses: @escaping FetchStatusesHandler,
        fetchContent: @escaping FetchContentHandler,
        persistContent: @escaping PersistContentHandler,
        onContentUpdate: @escaping ContentUpdateHandler,
        onReady: @escaping CompletionHandler,
        onFailure: @escaping CompletionHandler,
        onPollingError: @escaping PollingErrorHandler = { _, _ in }
    ) {
        self.pollingInterval = pollingInterval
        self.fetchStatuses = fetchStatuses
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
        lastSnapshots[content.id] = snapshot(from: content)
        ensurePollingTask()
    }

    func resumeBackgroundTracking(for contents: [Content]) {
        let activeIDs = Set(
            contents.filter { $0.status == .pending || $0.status == .processing }
                .map(\.id)
        )

        for content in contents where content.status == .pending || content.status == .processing {
            lastSnapshots[content.id] = snapshot(from: content)
            trackIfNeeded(content, behavior: .background)
        }

        for id in Array(behaviors.keys) where !activeIDs.contains(id) {
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
        behaviors[contentID] = nil
        lastSnapshots[contentID] = nil
        if behaviors.isEmpty {
            pollingTask?.cancel()
            pollingTask = nil
        }
    }

    func cancelAll() {
        for contentID in Array(behaviors.keys) {
            cancel(contentID: contentID)
        }
    }

    private func ensurePollingTask() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    private func pollLoop() async {
        defer {
            pollingTask = nil
        }

        while !Task.isCancelled {
            let activeIDs = Array(behaviors.keys)
            guard !activeIDs.isEmpty else { return }

            do {
                let statusSnapshots = try await fetchStatuses(activeIDs)
                let snapshotsByID = Dictionary(
                    uniqueKeysWithValues: statusSnapshots.map { ($0.id, $0) }
                )

                for contentID in activeIDs {
                    guard let snapshot = snapshotsByID[contentID] else {
                        continue
                    }
                    guard hasMeaningfulChange(snapshot, comparedTo: lastSnapshots[contentID]) else {
                        continue
                    }

                    lastSnapshots[contentID] = snapshot

                    do {
                        let content = try await fetchContent(contentID)
                        onContentUpdate(content)
                        await persistContent(content)
                        handleTerminalStateIfNeeded(contentID: contentID, content: content)
                    } catch is CancellationError {
                        return
                    } catch {
                        onPollingError(contentID, error)
                    }
                }

                try? await Task.sleep(for: pollingInterval)
            } catch is CancellationError {
                return
            } catch {
                for contentID in activeIDs {
                    onPollingError(contentID, error)
                }
                try? await Task.sleep(for: pollingInterval)
            }
        }
    }

    private func snapshot(from content: Content) -> ContentStatusSnapshot {
        ContentStatusSnapshot(
            id: content.id,
            status: content.status,
            updatedAt: content.updatedAt,
            l0Summary: content.l0Summary,
            processingError: nil
        )
    }

    private func hasMeaningfulChange(
        _ snapshot: ContentStatusSnapshot,
        comparedTo previous: ContentStatusSnapshot?
    ) -> Bool {
        guard let previous else {
            return true
        }
        return snapshot.status != previous.status
            || snapshot.updatedAt != previous.updatedAt
            || snapshot.l0Summary != previous.l0Summary
            || snapshot.processingError != previous.processingError
    }

    private func handleTerminalStateIfNeeded(contentID: String, content: Content) {
        let behavior = behaviors[contentID] ?? .background
        switch content.status {
        case .pending, .processing:
            return
        case .ready:
            behaviors[contentID] = nil
            lastSnapshots[contentID] = nil
            onReady(content, behavior)
        case .failed:
            behaviors[contentID] = nil
            lastSnapshots[contentID] = nil
            onFailure(content, behavior)
        }

        if behaviors.isEmpty {
            pollingTask?.cancel()
            pollingTask = nil
        }
    }
}
