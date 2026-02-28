import AVFoundation
import Foundation

// MARK: - Podcast Player View Model

@MainActor
@Observable
final class PodcastPlayerViewModel: NSObject {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var progress: Double = 0
    var currentChapterIndex: Int = 0
    var chapters: [(title: String, outlinePointIndex: Int?)] = []

    nonisolated(unsafe) private var player: AVPlayer?
    nonisolated(unsafe) private var timeObserver: Any?  // nonisolated(unsafe) needed for deinit access

    // MARK: - Loading

    func load(url: URL, chapters: [(title: String, outlinePointIndex: Int?)]) {
        self.chapters = chapters
        player = AVPlayer(url: url)
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 10),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = CMTimeGetSeconds(time)
                if self.duration > 0 {
                    self.progress = self.currentTime / self.duration
                }
            }
        }
        Task {
            if let dur = try? await player?.currentItem?.asset.load(.duration) {
                duration = CMTimeGetSeconds(dur)
            }
        }
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        if isPlaying { player?.pause() } else { player?.play() }
        isPlaying.toggle()
    }

    // MARK: - Chapter Navigation

    func nextChapter() {
        if currentChapterIndex < chapters.count - 1 { currentChapterIndex += 1 }
    }

    func previousChapter() {
        if currentChapterIndex > 0 { currentChapterIndex -= 1 }
    }

    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
    }

    // MARK: - Formatting

    static func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
