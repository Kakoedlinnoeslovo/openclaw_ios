import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionService.self) private var subscription
    @Environment(AppTheme.self) private var theme

    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    @State private var freeTrialEnabled = true
    @State private var errorMessage: String?
    @State private var selectedFallbackPlan: String = "yearly"
    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    providerHub
                        .padding(.top, 24)

                    headline

                    featureList

                    freeTrialToggle

                    planPicker

                    continueButton

                    footer
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding(.trailing, 20)
            .padding(.top, 16)
            .accessibilityIdentifier("paywall_dismiss")
        }
        .preferredColorScheme(.dark)
        .onAppear {
            appeared = true
            if selectedProduct == nil {
                selectedProduct = subscription.products.first(where: {
                    $0.id == AppConstants.Subscription.proYearlyID
                }) ?? subscription.products.first
            }
        }
    }

    // MARK: - Provider Hub

    private var providerHub: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [theme.accent.opacity(0.20), theme.accent.opacity(0.05), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 140
                    )
                )
                .frame(width: 280, height: 280)

            Circle()
                .stroke(theme.accent.opacity(0.08), lineWidth: 1)
                .frame(width: 160, height: 160)

            Circle()
                .stroke(theme.accent.opacity(0.05), lineWidth: 1)
                .frame(width: 240, height: 240)

            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: theme.heroGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 68, height: 68)
                    .shadow(color: theme.accent.opacity(0.4), radius: 20, y: 4)

                Image(systemName: "cpu.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
            }
            .scaleEffect(appeared ? 1 : 0.7)
            .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1), value: appeared)

            providerChip("sparkles", "GPT-5", angle: -60, radius: 100)
            providerChip("magnifyingglass", "Perplexity", angle: -20, radius: 110)
            providerChip("brain.head.profile", "ChatGPT", angle: 20, radius: 105)
            providerChip("wand.and.stars", "Claude", angle: 60, radius: 100)
            providerChip("bolt.fill", "Grok", angle: 120, radius: 100)
            providerChip("text.magnifyingglass", "DeepSeek", angle: 160, radius: 110)
            providerChip("function", "√x", angle: 200, radius: 105)
            providerChip("text.book.closed", "Aa", angle: 240, radius: 100)
        }
        .frame(height: 260)
    }

    private func providerChip(_ icon: String, _ name: String, angle: Double, radius: CGFloat) -> some View {
        let rad = angle * .pi / 180
        let x = cos(rad) * radius
        let y = sin(rad) * radius

        return ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 46, height: 46)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                )

            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(theme.accent)
        }
        .offset(x: x, y: y)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.2), value: appeared)
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(spacing: 6) {
            Text("Unlock New Possibilities")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Text("OpenClaw PRO")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: theme.accentGradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }

    // MARK: - Feature List

    private var featureList: some View {
        VStack(spacing: 0) {
            featureRow(icon: "sparkles.rectangle.stack", text: "Image Generation")
            featureRow(icon: "infinity", text: "Unlimited Messages")
            featureRow(icon: "keyboard", text: "Smart AI Keyboard")
            featureRow(icon: "star", text: "Best Value")
        }
        .padding(.vertical, 4)
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 32, height: 32)
                .background(theme.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9))

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Free Trial Toggle

    private var freeTrialToggle: some View {
        HStack {
            Text("Enable Free Trial")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            Toggle("", isOn: $freeTrialEnabled)
                .labelsHidden()
                .tint(theme.accent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
        .accessibilityIdentifier("paywall_trial_toggle")
    }

    // MARK: - Plan Picker

    private var planPicker: some View {
        VStack(spacing: 10) {
            if subscription.products.isEmpty {
                Button { selectedFallbackPlan = "yearly" } label: {
                    yearlyPlanCard(
                        title: "Yearly Plan",
                        subtitle: "12 mo · $49.99",
                        weeklyPrice: "$4.17/mo",
                        originalPrice: "$99.99/yr",
                        saveBadge: "BEST VALUE",
                        isSelected: selectedFallbackPlan == "yearly"
                    )
                }
                .buttonStyle(.plain)

                Button { selectedFallbackPlan = "monthly" } label: {
                    monthlyPlanCard(
                        title: "Monthly Plan",
                        monthlyPrice: "$9.99/mo",
                        originalPrice: "$19.99/mo",
                        isSelected: selectedFallbackPlan == "monthly"
                    )
                }
                .buttonStyle(.plain)
            } else {
                ForEach(subscription.products.sorted(by: { $0.price > $1.price }), id: \.id) { product in
                    let isYearly = product.id.contains("yearly")
                    let isSelected = selectedProduct?.id == product.id

                    Button { selectedProduct = product } label: {
                        if isYearly {
                            yearlyPlanCard(
                                title: "Yearly Plan",
                                subtitle: "12 mo · \(product.displayPrice)",
                                weeklyPrice: monthlyPrice(for: product),
                                originalPrice: originalYearlyPrice(for: product),
                                saveBadge: "BEST VALUE",
                                isSelected: isSelected
                            )
                        } else {
                            monthlyPlanCard(
                                title: "Monthly Plan",
                                monthlyPrice: product.displayPrice + "/mo",
                                originalPrice: originalMonthlyPrice(for: product),
                                isSelected: isSelected
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(isYearly ? "paywall_yearly" : "paywall_monthly")
                }
            }
        }
    }

    private func yearlyPlanCard(title: String, subtitle: String, weeklyPrice: String, originalPrice: String, saveBadge: String, isSelected: Bool) -> some View {
        ZStack(alignment: .top) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(originalPrice)
                        .font(.system(size: 12))
                        .strikethrough()
                        .foregroundStyle(.white.opacity(0.35))
                    Text(weeklyPrice)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(18)
            .padding(.top, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? theme.accent.opacity(0.10) : .white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected
                            ? AnyShapeStyle(LinearGradient(colors: theme.accentGradient, startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color.white.opacity(0.10)),
                        lineWidth: isSelected ? 2 : 1
                    )
            )

            Text(saveBadge)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    LinearGradient(colors: theme.accentGradient, startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(Capsule())
                .offset(y: -12)
        }
    }

    private func monthlyPlanCard(title: String, monthlyPrice: String, originalPrice: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            HStack(spacing: 8) {
                Text(originalPrice)
                    .font(.system(size: 13))
                    .strikethrough()
                    .foregroundStyle(.white.opacity(0.35))
                Text(monthlyPrice)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? theme.accent.opacity(0.10) : .white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isSelected
                        ? AnyShapeStyle(LinearGradient(colors: theme.accentGradient, startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.white.opacity(0.10)),
                    lineWidth: isSelected ? 2 : 1
                )
        )
    }

    private func monthlyPrice(for product: Product) -> String {
        let monthly = product.price / 12
        return String(format: "$%.2f/mo", NSDecimalNumber(decimal: monthly).doubleValue)
    }

    private func originalYearlyPrice(for product: Product) -> String {
        let original = product.price * 2
        return String(format: "$%.2f/yr", NSDecimalNumber(decimal: original).doubleValue)
    }

    private func originalMonthlyPrice(for product: Product) -> String {
        let original = product.price * 2
        return String(format: "$%.2f/mo", NSDecimalNumber(decimal: original).doubleValue)
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        VStack(spacing: 8) {
            Button { purchase() } label: {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    HStack(spacing: 8) {
                        Text("Continue")
                            .font(.system(size: 18, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }
            }
            .background(
                LinearGradient(
                    colors: theme.heroGradient,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: theme.accent.opacity(0.35), radius: 16, y: 6)
            .disabled(isPurchasing)
            .accessibilityIdentifier("paywall_continue")

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 24) {
            Button("Restore") {
                Task { await subscription.restorePurchases() }
            }
            Button("EULA") {}
            Button("Privacy") {}
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.35))
        .accessibilityIdentifier("paywall_footer")
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
