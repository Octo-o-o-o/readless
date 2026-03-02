import SwiftUI
import StoreKit
import Core

/// Reusable card component for displaying a subscription product
struct ProductCard: View {
    let product: Product
    let isCurrentPlan: Bool
    let isPurchasing: Bool
    let onPurchase: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(productName)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(product.displayPrice)
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    if hasFreeTrial {
                        Text("7-day free trial")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                Spacer()

                if isCurrentPlan {
                    Text("Current Plan")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }

            Divider()

            // Features
            VStack(alignment: .leading, spacing: 8) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 14))

                        Text(feature)
                            .font(.body)
                    }
                }
            }

            Spacer()

            // Purchase button
            Button {
                Task {
                    await onPurchase()
                }
            } label: {
                HStack {
                    if isPurchasing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(buttonTitle)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCurrentPlan || isPurchasing)
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrentPlan ? Color.blue : Color.clear, lineWidth: 2)
        )
    }

    // MARK: - Computed Properties

    private var productName: String {
        if product.id.contains("basic") {
            return "Basic"
        } else if product.id.contains("pro") {
            return "Pro"
        }
        return product.displayName
    }

    private var hasFreeTrial: Bool {
        // Both products have 7-day trial
        product.id.contains("monthly")
    }

    private var features: [String] {
        if product.id.contains("basic") {
            return [
                "Multi-level summaries",
                "PDF & Image OCR",
                "Full-text search",
                "Export to Markdown"
            ]
        } else if product.id.contains("pro") {
            return [
                "All Basic features",
                "AI Podcast generation",
                "Unlimited tags",
                "Priority support",
                "Early access to new features"
            ]
        }
        return []
    }

    private var buttonTitle: String {
        if isCurrentPlan {
            return "Active"
        } else if hasFreeTrial {
            return "Start Free Trial"
        } else {
            return "Subscribe"
        }
    }
}
