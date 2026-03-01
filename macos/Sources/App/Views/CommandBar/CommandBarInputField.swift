// macos/Sources/App/Views/CommandBar/CommandBarInputField.swift
import SwiftUI

struct CommandBarInputField: View {
    @Binding var query: String
    @FocusState private var isFocused: Bool

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
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var query = ""

    CommandBarInputField(query: $query)
        .frame(width: 600)
        .padding()
}
