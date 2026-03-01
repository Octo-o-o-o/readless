// macos/Sources/App/Views/CommandBar/CommandBarWindow.swift
import SwiftUI
import LiquidGlassKit
import AIServices

struct CommandBarWindow: View {
    @Environment(AICoordinator.self) private var coordinator
    @State private var query: String = ""

    var body: some View {
        VStack(spacing: 0) {
            CommandBarInputField(query: $query)

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
        .onChange(of: coordinator.isCommandBarVisible) { oldValue, newValue in
            if newValue {
                coordinator.resetSelection()
            }
        }
        .frame(width: 600)
        .frame(minHeight: 200, maxHeight: 500)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(radius: 40, x: 0, y: 20)
        .opacity(coordinator.isCommandBarVisible ? 1 : 0)
        .scaleEffect(coordinator.isCommandBarVisible ? 1.0 : 0.9)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: coordinator.isCommandBarVisible)
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
