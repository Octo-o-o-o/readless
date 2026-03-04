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
        VStack(spacing: Theme.space16) {
            // Progress
            Slider(value: $viewModel.progress, in: 0...1)
                .tint(Theme.accent)

            HStack {
                Text(PodcastPlayerViewModel.formatTime(viewModel.currentTime))
                Spacer()
                Text(PodcastPlayerViewModel.formatTime(viewModel.duration))
            }
            .font(Theme.captionFont.monospacedDigit())
            .foregroundStyle(Theme.textTertiary)

            // Controls
            HStack(spacing: Theme.space32) {
                Button { viewModel.previousChapter() } label: {
                    Image(systemName: "backward.end.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
                Button { viewModel.togglePlayPause() } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                }
                Button { viewModel.nextChapter() } label: {
                    Image(systemName: "forward.end.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)

            // Chapters
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.space8) {
                    ForEach(Array(viewModel.chapters.enumerated()), id: \.offset) { index, chapter in
                        HStack(spacing: Theme.space8) {
                            Circle()
                                .fill(index == viewModel.currentChapterIndex ? Theme.accent : Theme.borderMedium)
                                .frame(width: 6, height: 6)
                            Text(chapter.title)
                                .font(index == viewModel.currentChapterIndex ? Theme.l1Font : Theme.l2Font)
                                .foregroundStyle(index == viewModel.currentChapterIndex ? Theme.textPrimary : Theme.textSecondary)
                        }
                        .padding(.vertical, Theme.space2)
                    }
                }
            }
        }
        .padding(Theme.space20)
        .focusable()
        .onKeyPress(.space) { viewModel.togglePlayPause(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "[")) { _ in viewModel.previousChapter(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "]")) { _ in viewModel.nextChapter(); return .handled }
    }
}
