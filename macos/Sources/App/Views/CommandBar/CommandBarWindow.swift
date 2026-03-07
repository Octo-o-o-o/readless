// macos/Sources/App/Views/CommandBar/CommandBarWindow.swift
import SwiftUI
import AppKit
import AIServices
import UI

// Simple mock provider for input parsing (doesn't need actual AI)
private struct SimpleMockProvider: AIProviderProtocol {
    func chat(messages: [ChatMessage], model: String, options: AIChatOptions) async throws -> String {
        return ""
    }

    func analyzeImage(imageData: Data, prompt: String, model: String) async throws -> String {
        return ""
    }

    func analyzePDF(pdfData: Data, prompt: String, model: String) async throws -> String {
        return ""
    }

    func isReasoningModel(_ model: String) -> Bool {
        return false
    }
}

struct CommandBarWindow: View {
    @Environment(AICoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query: String = ""
    @State private var service: CommandBarService!
    @State private var clipboardContent: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Main panel
                VStack(spacing: 0) {
                    CommandBarInputField(
                        query: $query,
                        onDrop: { input in
                            Task {
                                await handleInput(input)
                            }
                        }
                    )

                    // Inline progress bar (replaces divider during loading)
                    if coordinator.commandBarImportState == .importing {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                            .padding(.horizontal, Theme.space16)
                            .padding(.top, Theme.space8)
                            .transition(.opacity)
                    } else {
                        Divider()
                            .padding(.horizontal)
                    }

                    // Content area: clipboard, results, or import states
                    ZStack {
                        switch coordinator.commandBarImportState {
                        case .idle:
                            idleContent
                                .transition(.opacity)

                        case .importing:
                            importingContent
                                .transition(.opacity)

                        case .success:
                            successContent
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
                    .frame(maxHeight: 400)
                    .animation(reduceMotion ? .none : .easeInOut(duration: 0.25), value: coordinator.commandBarImportState)
                }
                .frame(width: 600)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Command Bar")

                // Preview panel (shows on Tab or when content selected)
                if coordinator.showPreviewPanel {
                    Divider()

                    CommandBarPreviewPanel(content: coordinator.previewContent)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            // Error banner at bottom
            if let error = coordinator.errorMessage {
                ErrorBanner(
                    message: error,
                    onDismiss: {
                        coordinator.errorMessage = nil
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command Bar Window")
        .onKeyPress(.upArrow) {
            coordinator.selectPreviousResult()
            return .handled
        }
        .onKeyPress(.downArrow) {
            coordinator.selectNextResult()
            return .handled
        }
        .onKeyPress(.return) {
            guard coordinator.commandBarImportState == .idle else { return .ignored }
            Task {
                await coordinator.executeSelectedResult()
            }
            return .handled
        }
        .onKeyPress(.escape) {
            coordinator.hideCommandBar()
            return .handled
        }
        .onKeyPress(.tab) {
            coordinator.showPreviewPanel.toggle()
            return .handled
        }
        .accessibilityHint("Press Escape to close, up and down arrows to navigate, Enter to execute, Tab to toggle preview")
        .onAppear {
            service = CommandBarService(aiCoordinator: coordinator)
            service.search("")  // Show quick actions
            clipboardContent = NSPasteboard.general.string(forType: .string)
        }
        .onChange(of: query) { _, newValue in
            searchTask?.cancel()
            coordinator.errorMessage = nil
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                service.search(newValue)
            }
        }
        .onChange(of: coordinator.isCommandBarVisible) { oldValue, newValue in
            if newValue {
                coordinator.resetSelection()
                clipboardContent = NSPasteboard.general.string(forType: .string)
            }
        }
        .onChange(of: coordinator.commandBarImportState) { oldValue, newValue in
            if newValue == .success {
                // Auto-dismiss after brief success display
                Task {
                    try? await Task.sleep(for: .milliseconds(900))
                    guard coordinator.commandBarImportState == .success else { return }
                    coordinator.hideCommandBar()
                }
            }
        }
        .frame(minHeight: 200, maxHeight: 500)
        .background(.ultraThinMaterial)
        .cornerRadius(Theme.radiusLarge)
        .shadow(radius: 40, x: 0, y: 20)
        .opacity(coordinator.isCommandBarVisible ? 1 : 0)
        .scaleEffect(coordinator.isCommandBarVisible ? 1.0 : (reduceMotion ? 1.0 : 0.9))
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8), value: coordinator.isCommandBarVisible)
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8), value: coordinator.showPreviewPanel)
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8), value: coordinator.errorMessage)
    }

    // MARK: - Idle State Content

    @ViewBuilder
    private var idleContent: some View {
        VStack(spacing: 0) {
            // Clipboard paste shortcut
            if query.isEmpty, let clipboard = clipboardContent, !clipboard.isEmpty {
                clipboardPasteRow(clipboard)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                Divider()
                    .padding(.horizontal)
            }

            // Results list with subtle search loading
            ScrollView {
                if coordinator.isLoading {
                    HStack(spacing: Theme.space8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Searching…")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.space16)
                } else {
                    CommandBarResultsList(
                        results: coordinator.commandResults,
                        selectedIndex: coordinator.selectedResultIndex
                    )
                }
            }
            .accessibilityLabel("Search results")
            .accessibilityHint("\(coordinator.commandResults.count) results available")
        }
    }

    // MARK: - Importing State Content

    private var importingContent: some View {
        VStack(spacing: Theme.space16) {
            Spacer()

            Image(systemName: "arrow.down.doc")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.textSecondary)
                .symbolEffect(.pulse, options: .repeating)

            Text("Importing content…")
                .font(Theme.listTitleFont)
                .foregroundStyle(Theme.textPrimary)

            Text("Generating summary and outline")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(Theme.space16)
    }

    // MARK: - Success State Content

    private var successContent: some View {
        VStack(spacing: Theme.space12) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: coordinator.commandBarImportState)

            Text("Content imported")
                .font(Theme.listTitleFont)
                .foregroundStyle(Theme.textPrimary)

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(Theme.space16)
    }

    // MARK: - Clipboard Paste Row

    private func clipboardPasteRow(_ clipboard: String) -> some View {
        Button {
            Task {
                await service.importFromClipboard()
            }
        } label: {
            HStack(spacing: Theme.space12) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: Theme.space2) {
                    Text("Paste clipboard content")
                        .font(Theme.listTitleFont)
                        .foregroundStyle(Theme.textPrimary)

                    Text(clipboardPreview(clipboard))
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("⌘V")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.surfaceFloating.opacity(0.8))
                    )
            }
            .padding(.horizontal, Theme.space16)
            .padding(.vertical, Theme.space8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func clipboardPreview(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count > 80 {
            return String(cleaned.prefix(80)) + "…"
        }
        return cleaned
    }

    // MARK: - Input Handling

    private func handleInput(_ input: CommandBarInput) async {
        do {
            coordinator.isLoading = true
            defer { coordinator.isLoading = false }

            let parsed = try await InputParser(
                aiProvider: SimpleMockProvider(),
                config: AIServiceConfig.default.inputParsing
            ).parse(input)

            switch parsed {
            case .plainText(let text):
                query = text
            case .url(let url):
                query = url.absoluteString
            case .image, .pdf:
                coordinator.errorMessage = "Multi-modal analysis coming in Phase 3"
            case .command:
                break
            }
        } catch {
            coordinator.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    @State private var autoDismissTask: Task<Void, Never>?

    var body: some View {
        let errorText = friendlyMessage(for: message)

        return errorBannerContent(errorText: errorText)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Error")
            .accessibilityValue(errorText)
            .onAppear {
                autoDismissTask = Task {
                    try? await Task.sleep(for: .seconds(5))
                    if !Task.isCancelled {
                        await MainActor.run {
                            onDismiss()
                        }
                    }
                }
            }
            .onDisappear {
                autoDismissTask?.cancel()
            }
    }

    @ViewBuilder
    private func errorBannerContent(errorText: String) -> some View {
        HStack(spacing: Theme.space12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 16))
                .accessibilityHidden(true)

            Text(errorText)
                .font(Theme.metaFont)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.textSecondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss error")
        }
        .padding(Theme.space12)
        .background(Color.orange.opacity(0.15))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        }
        .cornerRadius(Theme.radiusSmall)
        .padding(.horizontal, Theme.space12)
        .padding(.bottom, Theme.space8)
    }

    private func friendlyMessage(for error: String) -> String {
        let lowercased = error.lowercased()

        if lowercased.contains("network") ||
           lowercased.contains("connection") ||
           lowercased.contains("unreachable") ||
           lowercased.contains("timeout") {
            return "Couldn't connect. Check your internet connection."
        }

        if lowercased.contains("parse") ||
           lowercased.contains("invalid") ||
           lowercased.contains("format") ||
           lowercased.contains("decode") {
            return "Couldn't understand that input. Try a different format?"
        }

        if lowercased.contains("file") ||
           lowercased.contains("read") ||
           lowercased.contains("permission") ||
           lowercased.contains("access") {
            return "Couldn't read that file. Make sure it's accessible."
        }

        if lowercased.contains("api") ||
           lowercased.contains("server") ||
           lowercased.contains("request") ||
           lowercased.contains("response") {
            return "Something went wrong with the server. Please try again."
        }

        if lowercased.contains("auth") ||
           lowercased.contains("token") ||
           lowercased.contains("unauthorized") {
            return "Authentication issue. Please sign in again."
        }

        if error.count > 100 {
            return "Something went wrong. Please try again."
        }

        return error
    }
}

// MARK: - Preview

#Preview("Normal State") {
    @Previewable @State var coordinator = AICoordinator()

    CommandBarWindow()
        .environment(coordinator)
        .onAppear {
            coordinator.isCommandBarVisible = true
            coordinator.commandResults = [
                .init(title: "Import from clipboard", subtitle: "⌘V", icon: "doc.text") {},
                .init(title: "Search all content", subtitle: "⌘F", icon: "magnifyingglass") {},
                .init(title: "Generate podcast", subtitle: "⌘P", icon: "mic") {}
            ]
        }
}

#Preview("With Error") {
    @Previewable @State var coordinator = AICoordinator()

    CommandBarWindow()
        .environment(coordinator)
        .onAppear {
            coordinator.isCommandBarVisible = true
            coordinator.errorMessage = "Network request failed due to timeout"
            coordinator.commandResults = [
                .init(title: "Import from clipboard", subtitle: "⌘V", icon: "doc.text") {},
                .init(title: "Search all content", subtitle: "⌘F", icon: "magnifyingglass") {}
            ]
        }
}

#Preview("Importing State") {
    @Previewable @State var coordinator = AICoordinator()

    CommandBarWindow()
        .environment(coordinator)
        .onAppear {
            coordinator.isCommandBarVisible = true
            coordinator.commandBarImportState = .importing
        }
}

#Preview("Success State") {
    @Previewable @State var coordinator = AICoordinator()

    CommandBarWindow()
        .environment(coordinator)
        .onAppear {
            coordinator.isCommandBarVisible = true
            coordinator.commandBarImportState = .success
        }
}
