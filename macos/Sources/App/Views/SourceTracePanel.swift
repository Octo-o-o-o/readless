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
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close source panel")
            }
            .padding(Theme.space16)

            Divider()

            // Paragraph list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.space12) {
                        ForEach(paragraphs, id: \.anchorID) { para in
                            HStack(alignment: .top, spacing: Theme.space8) {
                                // Anchor label
                                Text(para.anchorID)
                                    .font(Theme.citationFont)
                                    .foregroundStyle(Theme.citationColor)
                                    .frame(width: 30, alignment: .trailing)

                                // Paragraph text with highlight
                                Text(para.text)
                                    .font(Theme.l2Font)
                                    .lineSpacing(Theme.l2LineSpacing)
                                    .padding(Theme.space8)
                                    .background(
                                        RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                            .fill(
                                                para.anchorID == highlightAnchor
                                                    ? Theme.highlightBg
                                                    : .clear
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                            .strokeBorder(
                                                para.anchorID == highlightAnchor
                                                    ? Theme.highlightBorder
                                                    : .clear,
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .id(para.anchorID)
                        }
                    }
                    .padding(Theme.space16)
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
