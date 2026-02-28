import SwiftUI
import UI

// MARK: - Source Trace Panel

/// A sidebar panel that displays original source paragraphs with the relevant
/// anchor highlighted. Users can trace each outline point back to its source text.
struct SourceTracePanel: View {
    let paragraphs: [(anchorID: String, text: String)]
    let highlightAnchor: String?
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Original Text")
                    .font(.headline)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close source panel")
            }
            .padding()

            Divider()

            // Paragraph list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(paragraphs, id: \.anchorID) { para in
                            HStack(alignment: .top, spacing: 8) {
                                // Anchor label
                                Text(para.anchorID)
                                    .font(Theme.citationFont)
                                    .foregroundStyle(Theme.citationColor)
                                    .frame(width: 30, alignment: .trailing)

                                // Paragraph text with highlight
                                Text(para.text)
                                    .font(Theme.l2Font)
                                    .lineSpacing(Theme.lineSpacing)
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(
                                                para.anchorID == highlightAnchor
                                                    ? Color.yellow.opacity(0.15)
                                                    : .clear
                                            )
                                    )
                            }
                            .id(para.anchorID)
                        }
                    }
                    .padding()
                }
                .onAppear {
                    if let anchor = highlightAnchor {
                        withAnimation {
                            proxy.scrollTo(anchor, anchor: .center)
                        }
                    }
                }
                .onChange(of: highlightAnchor) { _, newAnchor in
                    if let anchor = newAnchor {
                        withAnimation {
                            proxy.scrollTo(anchor, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 350, maxWidth: 450)
        .background(.ultraThinMaterial)
    }
}
