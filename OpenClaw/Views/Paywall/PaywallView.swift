import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionService.self) private var subscription
    @Environment(AppTheme.self) private var theme

    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    @State private var freeTrialEnabled = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    topBar
                    providerHub
                    modelHeadline
                    freeTrialToggle
                    planPicker
                    continueButton
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            if selectedProduct == nil {
                selectedProduct = subscription.products.first(where: {
                    $0.id == AppConstants.Subscription.proYearlyID
                }) ?? subscription.products.first
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(Circle())
            }

            Spacer()

            Button("Restore") {
                Task { await subscription.restorePurchases() }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.3))
            .clipShape(Capsule())
        }
        .padding(.top, 8)
    }

    // MARK: - Provider Hub

    private var providerHub: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [theme.accent.opacity(0.12), theme.secondaryAccent.opacity(0.06), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 140
                    )
                )
                .frame(width: 280, height: 280)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: theme.accentGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: "cpu.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
            }

            providerChip("sparkles", "GPT-5")
                .offset(x: -70, y: -80)
            providerChip("magnifyingglass", "Perplexity")
                .offset(x: 70, y: -80)
            providerChip("brain.head.profile", "ChatGPT")
                .offset(x: -95, y: 0)
            providerChip("wand.and.stars", "Claude")
                .offset(x: 95, y: 0)
            providerChip("bolt.fill", "Grok")
                .offset(x: -70, y: 80)
            providerChip("text.magnifyingglass", "DeepSeek")
                .offset(x: 70, y: 80)
        }
        .frame(height: 240)
        .padding(.top, 4)
    }

    private func providerChip(_ icon: String, _ name: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(name)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    // MARK: - Model Headline

    private var modelHeadline: some View {
        VStack(spacing: 12) {
            Text("GPT-5, Grok, Claude 4")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 8) {
                featureRow(icon: "sparkles", text: "Create images and videos")
                featureRow(icon: "globe", text: "Search the web with AI")
                featureRow(icon: "waveform", text: "Talk naturally to AI")
            }
        }
    }

    // MARK: - Feature List (compact)

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(theme.accent)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Free Trial Toggle

    private var freeTrialToggle: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Free trial")
                    .font(.subheadline.weight(.medium))
                Text("3-day free trial")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("", isOn: $freeTrialEnabled)
                .labelsHidden()
                .tint(theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Plan Picker

    private var planPicker: some View {
        VStack(spacing: 10) {
            ForEach(subscription.products.sorted(by: { $0.price > $1.price }), id: \.id) { product in
                PlanCard(
                    product: product,
                    isSelected: selectedProduct?.id == product.id,
                    accentColor: theme.accent
                ) {
                    selectedProduct = product
                }
            }

            if subscription.products.isEmpty {
                PlanCardStatic(
                    title: "Yearly",
                    subtitle: "Only $69.99",
                    price: "$1.35",
                    period: "per week",
                    isBestOffer: true,
                    isSelected: true,
                    accentColor: theme.accent
                )
                PlanCardStatic(
                    title: "Weekly",
                    subtitle: "Cancel anytime",
                    price: "$6.99",
                    period: "per week",
                    isBestOffer: false,
                    isSelected: false,
                    accentColor: theme.accent
                )
            }
        }
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        VStack(spacing: 8) {
            Button {
                purchase()
            } label: {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    Text("Continue")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
            }
            .background(theme.buttonGradient)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .disabled(selectedProduct == nil || isPurchasing)
            .opacity(selectedProduct == nil ? 0.5 : 1)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 16) {
            Button("Terms") {}
                .foregroundStyle(.secondary)
            Text("|")
                .foregroundStyle(.quaternary)
            Button("Privacy") {}
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    // MARK: - Purchase

    private func purchase() {
        guard let product = selectedProduct else { return }
        isPurchasing = true
        Task {
            do {
                let success = try await subscription.purchase(product)
                if success { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
            }
            isPurchasing = false
        }
    }
}

// MARK: - Plan Card (StoreKit Product)

private struct PlanCard: View {
    let product: Product
    let isSelected: Bool
    let accentColor: Color
    let onTap: () -> Void

    private var isYearly: Bool {
        product.id.contains("yearly")
    }

    private var weeklyPrice: String {
        if isYearly {
            let weekly = product.price / 52
            return String(format: "$%.2f", NSDecimalNumber(decimal: weekly).doubleValue)
        }
        return product.displayPrice
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isYearly ? "Yearly" : "Weekly")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(isYearly ? "Only \(product.displayPrice)" : "Cancel anytime")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(weeklyPrice)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)

                        Text("per week")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? accentColor : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))

                if isYearly {
                    Text("Best offer")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(accentColor)
                        .clipShape(Capsule())
                        .offset(x: -12, y: -10)
                }
            }
        }
    }
}

// MARK: - Static Plan Card (fallback when products not loaded)

private struct PlanCardStatic: View {
    let title: String
    let subtitle: String
    let price: String
    let period: String
    let isBestOffer: Bool
    let isSelected: Bool
    let accentColor: Color

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(price)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(period)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? accentColor : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if isBestOffer {
                Text("Best offer")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accentColor)
                    .clipShape(Capsule())
                    .offset(x: -12, y: -10)
            }
        }
    }
}
