import SwiftUI
import UI

// MARK: - Podcast Player View

/// Audio player view for podcast playback with chapter navigation.
///
/// Controls:
///  - Space: Toggle play/pause
///  - `[` / `]`: Previous / next chapter
struct PodcastPlayerView: View {
    @State private var viewModel = PodcastPlayerViewModel()

    var body: some View {
        VStack(spacing: 16) {
            // Progress
            Slider(value: $viewModel.progress, in: 0...1)
                .tint(Theme.accent)

            HStack {
                Text(PodcastPlayerViewModel.formatTime(viewModel.currentTime))
                Spacer()
                Text(PodcastPlayerViewModel.formatTime(viewModel.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)

            // Controls
            HStack(spacing: 32) {
                Button { viewModel.previousChapter() } label: {
                    Image(systemName: "backward.end.fill")
                }
                Button { viewModel.togglePlayPause() } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                Button { viewModel.nextChapter() } label: {
                    Image(systemName: "forward.end.fill")
                }
            }
            .buttonStyle(.plain)

            // Chapters
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(viewModel.chapters.enumerated()), id: \.offset) { index, chapter in
                        HStack {
                            Circle()
                                .fill(index == viewModel.currentChapterIndex ? Theme.accent : .tertiary)
                                .frame(width: 6, height: 6)
                            Text(chapter.title)
                                .font(index == viewModel.currentChapterIndex ? Theme.l1Font : Theme.l2Font)
                                .foregroundStyle(index == viewModel.currentChapterIndex ? .primary : .secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .focusable()
        .onKeyPress(.space) { viewModel.togglePlayPause(); return .handled }
        .onKeyPress(characters: "[") { viewModel.previousChapter(); return .handled }
        .onKeyPress(characters: "]") { viewModel.nextChapter(); return .handled }
    }
}
