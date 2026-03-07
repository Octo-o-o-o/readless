// macos/Sources/App/Views/CommandBar/CommandBarInputField.swift
import SwiftUI
import UniformTypeIdentifiers
import AIServices
import UI

struct CommandBarInputField: View {
    @Binding var query: String
    @FocusState private var isFocused: Bool
    var onDrop: ((CommandBarInput) -> Void)?
    @State private var isDropTargeted = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.space12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
                .font(.title3)
                .padding(.top, 6)
                .accessibilityHidden(true)

            TextField("Type to search or paste URL...", text: $query, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title2)
                .lineLimit(1...5)
                .focused($isFocused)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isFocused = true
                    }
                }
                .accessibilityLabel("Command search field")
                .accessibilityHint("Type to search, paste URLs, or drag files here")
        }
        .padding(Theme.space16)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .fill(Theme.surfaceFloating.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .stroke(isFocused ? Theme.borderFocused : Color.clear, lineWidth: 2)
                )
        )
        .padding(.horizontal, Theme.space16)
        .padding(.top, Theme.space16)
        .onDrop(of: [.fileURL, .image, .pdf], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .stroke(isDropTargeted ? Theme.accent : Color.clear, style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search input")
        .accessibilityValue(query.isEmpty ? "Empty" : query)
        .accessibilityHint(isDropTargeted ? "Drop zone active" : "Type to search or drag files")
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                    let onDrop = self.onDrop
                    Task.detached(priority: .userInitiated) {
                        guard let fileData = try? Data(contentsOf: url) else { return }
                        let ext = url.pathExtension.lowercased()
                        let input: CommandBarInput
                        if ext == "pdf" {
                            input = .pdf(fileData)
                        } else if ["jpg", "jpeg", "png"].contains(ext) {
                            input = .image(fileData)
                        } else if let text = String(data: fileData, encoding: .utf8) {
                            input = .text(text)
                        } else {
                            return
                        }
                        await MainActor.run { onDrop?(input) }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    guard let data = data else { return }
                    Task { @MainActor in
                        onDrop?(.image(data))
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var query = ""

    CommandBarInputField(query: $query)
        .frame(width: 600)
        .padding()
}
