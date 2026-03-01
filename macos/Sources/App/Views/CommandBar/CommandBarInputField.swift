// macos/Sources/App/Views/CommandBar/CommandBarInputField.swift
import SwiftUI
import UniformTypeIdentifiers
import AIServices

struct CommandBarInputField: View {
    @Binding var query: String
    @FocusState private var isFocused: Bool
    var onDrop: ((CommandBarInput) -> Void)?
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.title3)

            TextField("Type to search or paste URL...", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($isFocused)
                .onAppear {
                    // Auto-focus when Command Bar appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isFocused = true
                    }
                }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        )
        .padding(.horizontal)
        .padding(.top)
        .onDrop(of: [.fileURL, .image, .pdf], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDropTargeted ? Color.accentColor : Color.clear, style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
        )
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                    Task { @MainActor in
                        if let fileData = try? Data(contentsOf: url) {
                            if url.pathExtension.lowercased() == "pdf" {
                                onDrop?(.pdf(fileData))
                            } else if ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()) {
                                onDrop?(.image(fileData))
                            } else {
                                if let text = String(data: fileData, encoding: .utf8) {
                                    onDrop?(.text(text))
                                }
                            }
                        }
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
