import Foundation
import StoreKit

@MainActor
final class PurchaseService: ObservableObject {
    static let shared = PurchaseService()

    static let productId = "com.livelens.app.unlimited"
    static let freeLimit = 3

    @Published private(set) var isPurchased: Bool = false
    @Published private(set) var isLoading: Bool = false

    private var updates: Task<Void, Never>?

    private init() {
        isPurchased = UserDefaults.standard.bool(forKey: "isPurchased")
        updates = listenForTransactions()
        Task { await refreshPurchaseStatus() }
    }

    deinit {
        updates?.cancel()
    }

    var canAnalyze: Bool {
        if isPurchased { return true }
        let done = HistoryStore.shared.entries.filter { $0.status == .done }.count
        return done < Self.freeLimit || rewardedRemaining > 0
    }

    var remainingFree: Int {
        max(0, Self.freeLimit - HistoryStore.shared.entries.filter { $0.status == .done }.count)
    }

    // 広告視聴で付与された残り回数
    var rewardedRemaining: Int {
        UserDefaults.standard.integer(forKey: "rewardedRemaining")
    }

    func consumeRewardedIfNeeded() {
        guard !isPurchased else { return }
        let done = HistoryStore.shared.entries.filter { $0.status == .done }.count
        if done >= Self.freeLimit && rewardedRemaining > 0 {
            UserDefaults.standard.set(rewardedRemaining - 1, forKey: "rewardedRemaining")
        }
    }

    func grantRewardedAnalysis() {
        UserDefaults.standard.set(rewardedRemaining + 1, forKey: "rewardedRemaining")
    }

    func purchase() async throws {
        isLoading = true
        defer { isLoading = false }

        guard let product = try await Product.products(for: [Self.productId]).first else {
            throw PurchaseError.productNotFound
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            setPurchased(true)
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }

    func restore() async throws {
        isLoading = true
        defer { isLoading = false }
        try await AppStore.sync()
        await refreshPurchaseStatus()
    }

    private func refreshPurchaseStatus() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == Self.productId {
                setPurchased(true)
                return
            }
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                if case .verified(let tx) = result, tx.productID == Self.productId {
                    await tx.finish()
                    await MainActor.run { self.setPurchased(true) }
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified: throw PurchaseError.verificationFailed
        }
    }

    private func setPurchased(_ value: Bool) {
        isPurchased = value
        UserDefaults.standard.set(value, forKey: "isPurchased")
    }
}

enum PurchaseError: LocalizedError {
    case productNotFound
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .productNotFound: return "商品情報を取得できませんでした"
        case .verificationFailed: return "購入の確認に失敗しました"
        }
    }
}
