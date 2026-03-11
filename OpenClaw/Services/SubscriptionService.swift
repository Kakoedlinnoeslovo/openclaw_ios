import Foundation
import StoreKit

@Observable
final class SubscriptionService {
    static let shared = SubscriptionService()

    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var currentTier: User.SubscriptionTier = .free
    var usage: UsageStats?
    var subscriptionInfo: SubscriptionInfo?
    var isLoading = false

    private var updateListenerTask: Task<Void, Error>?

    private let productIDs = [
        AppConstants.Subscription.proMonthlyID,
        AppConstants.Subscription.proYearlyID,
        AppConstants.Subscription.teamMonthlyID
    ]

    private init() {
        updateListenerTask = listenForTransactions()
    }

    deinit {
        updateListenerTask?.cancel()
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: productIDs)
                .sorted { $0.price < $1.price }
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateSubscriptionStatus()
            await transaction.finish()
            return true
        case .userCancelled:
            return false
        case .pending:
            return false
        @unknown default:
            return false
        }
    }

    func updateSubscriptionStatus() async {
        var newPurchased: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                newPurchased.insert(transaction.productID)
            }
        }

        purchasedProductIDs = newPurchased

        if newPurchased.contains(AppConstants.Subscription.teamMonthlyID) {
            currentTier = .team
        } else if newPurchased.contains(AppConstants.Subscription.proMonthlyID) ||
                  newPurchased.contains(AppConstants.Subscription.proYearlyID) {
            currentTier = .pro
        } else {
            currentTier = .free
        }
    }

    func fetchUsage() async throws {
        usage = try await APIClient.shared.get("/usage")
    }

    func fetchSubscription() async throws {
        subscriptionInfo = try await APIClient.shared.get("/subscription")
    }

    func verifyReceipt(receiptData: String, productId: String) async throws {
        struct VerifyBody: Codable {
            let receiptData: String
            let productId: String
        }
        struct VerifyResponse: Codable {
            let status: String
            let tier: String
        }
        let _: VerifyResponse = try await APIClient.shared.post(
            "/subscription/verify",
            body: VerifyBody(receiptData: receiptData, productId: productId)
        )
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await updateSubscriptionStatus()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let _ = try? self?.checkVerified(result) {
                    await self?.updateSubscriptionStatus()
                }
            }
        }
    }

    enum StoreError: Error {
        case failedVerification
    }
}
