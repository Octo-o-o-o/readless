import SwiftUI
import StoreKit
import Core
import UI

/// Reusable card component for displaying a subscription product
struct ProductCard: View {
    let product: Product
    let isCurrentPlan: Bool
    let isPurchasing: Bool
    let onPurchase: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: Theme.space4) {
                    Text(productName)
                        .font(.system(size: 20, weight: .semibold))

                    Text(product.displayPrice)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textSecondary)

                    if hasFreeTrial {
                        Text("7-day free trial")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.accent)
                    }
                }

                Spacer()

                if isCurrentPlan {
                    Text("Current Plan")
                        .font(Theme.captionFont)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.space12)
                        .padding(.vertical, Theme.space6)
                        .background(Theme.accent)
                        .cornerRadius(Theme.radiusSmall)
                }
            }

            Divider()

            // Features
            VStack(alignment: .leading, spacing: Theme.space8) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: Theme.space8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 14))

                        Text(feature)
                            .font(Theme.metaFont)
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
        .padding(Theme.space20)
        .background(Theme.surfaceFloating)
        .cornerRadius(Theme.radiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .stroke(isCurrentPlan ? Theme.accent : Color.clear, lineWidth: 2)
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
