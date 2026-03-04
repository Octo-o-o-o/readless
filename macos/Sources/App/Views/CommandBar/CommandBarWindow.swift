// macos/Sources/App/Views/CommandBar/CommandBarWindow.swift
import SwiftUI
import LiquidGlassKit
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

                    Divider()
                        .padding(.horizontal)

                    ScrollView {
                        CommandBarResultsList(
                            results: coordinator.commandResults,
                            selectedIndex: coordinator.selectedResultIndex
                        )
                    }
                    .frame(maxHeight: 400)
                    .accessibilityLabel("Search results")
                    .accessibilityHint("\(coordinator.commandResults.count) results available")
                    .overlay {
                        if coordinator.isLoading {
                            Color.black.opacity(0.2)
                                .overlay {
                                    ProgressView()
                                        .controlSize(.large)
                                        .scaleEffect(1.2)
                                        .accessibilityLabel("Loading results")
                                }
                        }
                    }
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
        }
        .onChange(of: query) { oldValue, newValue in
            service.search(newValue)
            // Clear error on new search
            coordinator.errorMessage = nil
        }
        .onChange(of: coordinator.isCommandBarVisible) { oldValue, newValue in
            if newValue {
                coordinator.resetSelection()
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

    private func handleInput(_ input: CommandBarInput) async {
        do {
            coordinator.isLoading = true
            defer { coordinator.isLoading = false }

            let parsed = try await InputParser(
                aiProvider: SimpleMockProvider(),
                config: AIServiceConfig.default.inputParsing
            ).parse(input)

            // Handle parsed input
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
                // Auto-dismiss after 5 seconds
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

        // Network errors
        if lowercased.contains("network") ||
           lowercased.contains("connection") ||
           lowercased.contains("unreachable") ||
           lowercased.contains("timeout") {
            return "Couldn't connect. Check your internet connection."
        }

        // Parse errors
        if lowercased.contains("parse") ||
           lowercased.contains("invalid") ||
           lowercased.contains("format") ||
           lowercased.contains("decode") {
            return "Couldn't understand that input. Try a different format?"
        }

        // File errors
        if lowercased.contains("file") ||
           lowercased.contains("read") ||
           lowercased.contains("permission") ||
           lowercased.contains("access") {
            return "Couldn't read that file. Make sure it's accessible."
        }

        // API errors
        if lowercased.contains("api") ||
           lowercased.contains("server") ||
           lowercased.contains("request") ||
           lowercased.contains("response") {
            return "Something went wrong with the server. Please try again."
        }

        // Authentication errors
        if lowercased.contains("auth") ||
           lowercased.contains("token") ||
           lowercased.contains("unauthorized") {
            return "Authentication issue. Please sign in again."
        }

        // Generic fallback - keep it short and friendly
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

#Preview("Loading State") {
    @Previewable @State var coordinator = AICoordinator()

    CommandBarWindow()
        .environment(coordinator)
        .onAppear {
            coordinator.isCommandBarVisible = true
            coordinator.isLoading = true
            coordinator.commandResults = [
                .init(title: "Import from clipboard", subtitle: "⌘V", icon: "doc.text") {},
                .init(title: "Search all content", subtitle: "⌘F", icon: "magnifyingglass") {}
            ]
        }
}
