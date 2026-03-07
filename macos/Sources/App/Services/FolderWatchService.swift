import Foundation
import CoreServices

/// Monitors user-configured directories for new files using FSEvents and triggers
/// automatic content import via a callback.
///
/// Supported file types: PDF, TXT, MD, DOCX, PNG, JPG, JPEG, HTML.
/// On start the service snapshots existing files so that only *newly added* files
/// are reported to the callback.
final class FolderWatchService {

    // MARK: - Properties

    private var stream: FSEventStreamRef?
    private var retainedSelf: Unmanaged<FolderWatchService>?
    private let callback: ([String]) -> Void
    private var watchedPaths: [String] = []
    private var knownFiles: Set<String> = []

    // MARK: - Initialisation

    /// Creates a new folder watch service.
    ///
    /// - Parameter callback: Called on the main thread with an array of newly detected
    ///   file paths whenever files matching the supported extensions appear in a
    ///   watched directory.
    init(callback: @escaping ([String]) -> Void) {
        self.callback = callback
    }

    // MARK: - Public API

    /// Begins watching the given directory paths for new files.
    ///
    /// Any previously active watch is stopped first. Existing files inside the
    /// directories are recorded so they are not reported as new.
    ///
    /// - Parameter paths: Absolute paths to the directories to monitor.
    func watch(paths: [String]) {
        stop()
        watchedPaths = paths

        // Snapshot existing files so we only report genuinely new arrivals.
        for path in paths {
            if let files = try? FileManager.default.contentsOfDirectory(atPath: path) {
                for file in files {
                    knownFiles.insert("\(path)/\(file)")
                }
            }
        }

        let retained = Unmanaged.passRetained(self)
        retainedSelf = retained
        var context = FSEventStreamContext()
        context.info = retained.toOpaque()

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, clientInfo, numEvents, eventPaths, _, _ in
                guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                let service = Unmanaged<FolderWatchService>.fromOpaque(clientInfo!).takeUnretainedValue()
                service.handleEvents(paths: paths)
            },
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )

        guard let stream else { return }
        // Dispatch on main to avoid data race on knownFiles (callback already hops to main).
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    /// Stops the current file-system event stream, if any.
    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        // Balance the passRetained from watch(paths:)
        retainedSelf?.release()
        retainedSelf = nil
    }

    deinit { stop() }

    // MARK: - Event Handling

    /// Filters incoming FSEvents to only new files with supported extensions,
    /// then forwards them to the callback on the main thread.
    private func handleEvents(paths: [String]) {
        let supportedExtensions: Set<String> = ["pdf", "txt", "md", "docx", "png", "jpg", "jpeg", "html"]
        var newFiles: [String] = []

        for path in paths {
            guard !knownFiles.contains(path) else { continue }
            let ext = (path as NSString).pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }
            guard FileManager.default.fileExists(atPath: path) else { continue }
            knownFiles.insert(path)
            newFiles.append(path)
        }

        if !newFiles.isEmpty {
            // Already on main queue (FSEvent stream dispatched to main)
            callback(newFiles)
        }
    }
}
