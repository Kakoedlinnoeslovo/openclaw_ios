import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionService.self) private var subscription
    @Environment(AppTheme.self) private var theme

    /// When true, shown inside onboarding; dismiss is not used and `onFunnelFinished` is required to enter the app.
    var embeddedInFunnel: Bool = false
    var onFunnelFinished: (() -> Void)?

    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    @State private var freeTrialEnabled = true
    @State private var errorMessage: String?
    @State private var appeared = false
    @State private var fallbackPlan: FallbackPlan = .weekly

    private enum FallbackPlan: String {
        case yearly, weekly
    }

    init(embeddedInFunnel: Bool = false, onFunnelFinished: (() -> Void)? = nil) {
        self.embeddedInFunnel = embeddedInFunnel
        self.onFunnelFinished = onFunnelFinished
    }

    var body: some View {
        ZStack(alignment: .top) {
            if !embeddedInFunnel {
                Color.black.ignoresSafeArea()
                OnboardingSpiralBackground(focal: .center)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    Color.clear.frame(height: 52)
                    providerHub
                    headline
                    featureList
                    freeTrialToggle
                    planPicker
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                paywallBottomBar
            }

            topBar
                .zIndex(1)
                .allowsHitTesting(true)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            appeared = true
            syncSelectionWithTrialToggle()
        }
        .onChange(of: freeTrialEnabled) { _, _ in
            syncSelectionWithTrialToggle()
        }
        .onChange(of: subscription.products.count) { _, _ in
            syncSelectionWithTrialToggle()
        }
    }

    // MARK: - Top bar

    /// Pinned above home indicator so Continue is always visible without scrolling.
    private var paywallBottomBar: some View {
        VStack(spacing: 10) {
            continueButton
            footerLinks
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0),
                        Color.black.opacity(0.55),
                        Color.black,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 36)

                Color.black
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                completeFunnelIfNeeded()
                if !embeddedInFunnel { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .background(OnboardingPalette.skipPill)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("paywall_dismiss")

            Spacer()

            Button {
                Task { await subscription.restorePurchases() }
            } label: {
                Text("Restore")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(OnboardingPalette.skipPill)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("paywall_restore")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    // MARK: - Provider hub

    private var providerHub: some View {
        ZStack {
            EllipticalNebulaGlow()
                .frame(height: 168)
                .offset(y: -14)

            TimelineView(.animation(minimumInterval: 1 / 24, paused: false)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )

                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white)

                    paywallChip("Veo 3", "star.fill", angle: -58, radius: 92, time: t)
                    paywallChip("Perplexity", "book.closed.fill", angle: -18, radius: 100, time: t)
                    paywallChip("ChatGPT", "bubble.left.and.bubble.right.fill", angle: 22, radius: 96, time: t)
                    paywallChip("Claude", "sun.max.fill", angle: 58, radius: 92, time: t)
                    paywallChip("Grok 4", "location.north.circle.fill", angle: 118, radius: 92, time: t)
                    paywallChip("DeepSeek", "fish.fill", angle: 162, radius: 98, time: t)
                }
                .frame(height: 200)
            }
        }
        .opacity(appeared ? 1 : 0.85)
        .scaleEffect(appeared ? 1 : 0.96)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: appeared)
    }

    private func paywallChip(_ title: String, _ icon: String, angle: Double, radius: CGFloat, time: TimeInterval) -> some View {
        let rad = angle * .pi / 180
        let bob = sin(time * 1.25 + angle * 0.03) * 3.2
        let x = cos(rad) * radius
        let y = sin(rad) * radius + bob
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .offset(x: x, y: y)
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(spacing: 10) {
            Text("GPT-5.4, Grok 4, Veo 3.1")
                .font(OnboardingTypography.paywallHeadline)
                .foregroundStyle(OnboardingPalette.titleGradient)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("paywall_headline")
        }
    }

    // MARK: - Features

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            paywallFeatureRow(icon: "sparkles.rectangle.stack", title: "Create images and videos")
            paywallFeatureRow(icon: "safari.fill", title: "Search the web with AI")
            paywallFeatureRow(icon: "waveform", title: "Talk naturally to AI")
        }
        .padding(.vertical, 4)
    }

    private func paywallFeatureRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
            Text(title)
                .font(OnboardingTypography.paywallFeature)
                .foregroundStyle(.white)
            Spacer()
        }
    }

    // MARK: - Trial toggle

    private var freeTrialToggle: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Free trial")
                    .font(OnboardingTypography.paywallFeature)
                    .foregroundStyle(.white)
                Text("3-day free trial")
                    .font(OnboardingTypography.planMeta)
                    .foregroundStyle(OnboardingPalette.muted)
            }
            Spacer()
            Toggle("", isOn: $freeTrialEnabled)
                .labelsHidden()
                .tint(OnboardingPalette.iosBlue)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(OnboardingPalette.chipFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("paywall_trial_toggle")
    }

    // MARK: - Plans

    private var planPicker: some View {
        VStack(spacing: 12) {
            if subscription.products.isEmpty {
                fallbackYearlyCard
                fallbackWeeklyCard
            } else {
                yearlyProductCard
                weeklyProductCard
            }
        }
    }

    private var yearlyProduct: Product? {
        subscription.products.first { $0.id == AppConstants.Subscription.proYearlyID }
    }

    private var weeklyProduct: Product? {
        subscription.products.first { $0.id == AppConstants.Subscription.proWeeklyID }
    }

    private func syncSelectionWithTrialToggle() {
        if freeTrialEnabled {
            selectedProduct = weeklyProduct
            fallbackPlan = .weekly
        } else {
            selectedProduct = yearlyProduct
            fallbackPlan = .yearly
        }
    }

    @ViewBuilder
    private var yearlyProductCard: some View {
        if let p = yearlyProduct {
            planCardButton(
                product: p,
                isYearly: true,
                isSelected: selectedProduct?.id == p.id,
                weeklyEquivalent: formatPerWeek(from: p.price, periodsPerYear: 52)
            )
        }
    }

    @ViewBuilder
    private var weeklyProductCard: some View {
        if let p = weeklyProduct {
            planCardButton(
                product: p,
                isYearly: false,
                isSelected: selectedProduct?.id == p.id,
                weeklyEquivalent: nil
            )
        }
    }

    private func planCardButton(
        product: Product,
        isYearly: Bool,
        isSelected: Bool,
        weeklyEquivalent: String?
    ) -> some View {
        Button {
            selectedProduct = product
        } label: {
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isYearly ? "Yearly" : "Weekly")
                            .font(OnboardingTypography.planTitle)
                            .foregroundStyle(.white)
                        if isYearly {
                            Text("Only \(product.displayPrice)")
                                .font(OnboardingTypography.planMeta)
                                .foregroundStyle(OnboardingPalette.muted)
                        } else {
                            Text(freeTrialEnabled ? "3-day free trial" : "Cancel anytime")
                                .font(OnboardingTypography.planMeta)
                                .foregroundStyle(OnboardingPalette.muted)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let weeklyEquivalent {
                            Text(weeklyEquivalent)
                                .font(OnboardingTypography.planPrice)
                                .foregroundStyle(.white)
                            Text("per week")
                                .font(OnboardingTypography.planUnit)
                                .foregroundStyle(OnboardingPalette.muted)
                        } else {
                            Text(product.displayPrice)
                                .font(OnboardingTypography.planPrice)
                                .foregroundStyle(.white)
                            Text("per week")
                                .font(OnboardingTypography.planUnit)
                                .foregroundStyle(OnboardingPalette.muted)
                        }
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(OnboardingPalette.chipFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            isSelected ? OnboardingPalette.iosBlue : Color.white.opacity(0.1),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

                if isYearly {
                    Text("Best offer")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(OnboardingPalette.iosBlue)
                        .clipShape(Capsule())
                        .offset(x: -8, y: -10)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isSelected)
        .accessibilityIdentifier(isYearly ? "paywall_yearly" : "paywall_weekly")
    }

    private func formatPerWeek(from yearlyPrice: Decimal, periodsPerYear: Int) -> String {
        let per = yearlyPrice / Decimal(periodsPerYear)
        let d = NSDecimalNumber(decimal: per).doubleValue
        return String(format: "$%.2f", d)
    }

    private var fallbackYearlyCard: some View {
        Button {
            fallbackPlan = .yearly
            selectedProduct = nil
        } label: {
            ZStack(alignment: .topTrailing) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Yearly")
                            .font(OnboardingTypography.planTitle)
                            .foregroundStyle(.white)
                        Text("Only $69.99")
                            .font(OnboardingTypography.planMeta)
                            .foregroundStyle(OnboardingPalette.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("$1.35")
                            .font(OnboardingTypography.planPrice)
                            .foregroundStyle(.white)
                        Text("per week")
                            .font(OnboardingTypography.planUnit)
                            .foregroundStyle(OnboardingPalette.muted)
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(OnboardingPalette.chipFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            fallbackPlan == .yearly ? OnboardingPalette.iosBlue : Color.white.opacity(0.1),
                            lineWidth: fallbackPlan == .yearly ? 2 : 1
                        )
                )
                Text("Best offer")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(OnboardingPalette.iosBlue)
                    .clipShape(Capsule())
                    .offset(x: -8, y: -10)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: fallbackPlan)
        .accessibilityIdentifier("paywall_yearly")
    }

    private var fallbackWeeklyCard: some View {
        Button {
            fallbackPlan = .weekly
            selectedProduct = nil
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly")
                        .font(OnboardingTypography.planTitle)
                        .foregroundStyle(.white)
                    Text(freeTrialEnabled ? "3-day free trial" : "Cancel anytime")
                        .font(OnboardingTypography.planMeta)
                        .foregroundStyle(OnboardingPalette.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("$6.99")
                        .font(OnboardingTypography.planPrice)
                        .foregroundStyle(.white)
                    Text("per week")
                        .font(OnboardingTypography.planUnit)
                        .foregroundStyle(OnboardingPalette.muted)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(OnboardingPalette.chipFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        fallbackPlan == .weekly ? OnboardingPalette.iosBlue : Color.white.opacity(0.1),
                        lineWidth: fallbackPlan == .weekly ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: fallbackPlan)
        .accessibilityIdentifier("paywall_weekly")
    }

    // MARK: - Continue

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
                        .font(OnboardingTypography.cta)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
            }
            .background(OnboardingPalette.iosBlue)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .disabled(isPurchasing)
            .accessibilityIdentifier("paywall_continue")

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var footerLinks: some View {
        HStack(spacing: 8) {
            Link("Terms", destination: AppConstants.Legal.termsURL)
            Text("|").foregroundStyle(OnboardingPalette.muted.opacity(0.5))
            Link("Privacy", destination: AppConstants.Legal.privacyURL)
        }
        .font(OnboardingTypography.caption)
        .foregroundStyle(OnboardingPalette.muted)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("paywall_footer")
    }

    // MARK: - Actions

    private func completeFunnelIfNeeded() {
        onFunnelFinished?()
    }

    private func purchase() {
        if subscription.products.isEmpty {
            errorMessage = "Subscriptions aren’t available yet. Check App Store Connect configuration."
            return
        }
        guard let product = selectedProduct else {
            errorMessage = "Pick a plan to continue."
            return
        }
        isPurchasing = true
        errorMessage = nil
        Task {
            do {
                let success = try await subscription.purchase(product)
                if success {
                    completeFunnelIfNeeded()
                    if !embeddedInFunnel { dismiss() }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isPurchasing = false
        }
    }
}

// MARK: - Nebula background

private struct EllipticalNebulaGlow: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.15, green: 0.92, blue: 0.88).opacity(0.42),
                            Color(red: 0.2, green: 0.45, blue: 0.95).opacity(0.18),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 16,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 210)
                .offset(x: -56, y: -8)
                .blur(radius: 30)
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.38, green: 0.15, blue: 0.92).opacity(0.4),
                            Color(red: 0.12, green: 0.08, blue: 0.35).opacity(0.12),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 24,
                        endRadius: 170
                    )
                )
                .frame(width: 320, height: 200)
                .offset(x: 58, y: 6)
                .blur(radius: 34)
        }
    }
}
