// macos/Sources/App/Views/CommandBar/CommandBarWindow.swift
import SwiftUI
import LiquidGlassKit
import AIServices

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
    @State private var query: String = ""

    var body: some View {
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
            }
            .frame(width: 600)

            // Preview panel (shows on Tab or when content selected)
            if coordinator.showPreviewPanel {
                Divider()

                CommandBarPreviewPanel(content: coordinator.previewContent)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
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
        .onChange(of: coordinator.isCommandBarVisible) { oldValue, newValue in
            if newValue {
                coordinator.resetSelection()
            }
        }
        .frame(minHeight: 200, maxHeight: 500)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(radius: 40, x: 0, y: 20)
        .opacity(coordinator.isCommandBarVisible ? 1 : 0)
        .scaleEffect(coordinator.isCommandBarVisible ? 1.0 : 0.9)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: coordinator.isCommandBarVisible)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: coordinator.showPreviewPanel)
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

// MARK: - Preview

#Preview {
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
