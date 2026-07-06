import Foundation
import StoreKit

/// StoreKit 2 subscription state for タナミル チーム (spec: monetization plan,
/// docs/MONETIZATION_PLAN_JA.md). Sharing a project (creating NEW shares)
/// requires an active subscription; participants join for free, and shares
/// created before the paywall keep working (grandfathered — the gate only
/// covers `.notShared → share` transitions).
///
/// 昭和商会 members get the subscription for free via App Store OFFER CODES
/// (redeemed through Apple's standard sheet) — never via a homegrown unlock
/// code, which would violate App Review Guideline 3.1.1.
@MainActor
final class EntitlementService: ObservableObject {

    static let monthlyID = "com.tenten.tanamiru.team.monthly"
    static let yearlyID  = "com.tenten.tanamiru.team.yearly"
    static let productIDs: Set<String> = [monthlyID, yearlyID]

    /// True while a verified, unrevoked subscription transaction exists.
    /// StoreKit 2 caches entitlements locally, so this stays correct offline.
    @Published private(set) var hasTeamFeatures = false
    @Published private(set) var products: [StoreKit.Product] = []
    @Published private(set) var purchasing = false

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            // Covers purchases, renewals, refunds AND offer-code redemptions
            // done in the App Store app while we run.
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
        Task {
            await refreshEntitlement()
            await loadProducts()
        }
    }

    deinit { updatesTask?.cancel() }

    func refreshEntitlement() async {
        var active = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                active = true
            }
        }
        hasTeamFeatures = active
    }

    func loadProducts() async {
        var loaded = (try? await StoreKit.Product.products(for: Self.productIDs)) ?? []
        loaded.sort { $0.price < $1.price } // monthly first
        products = loaded
    }

    /// Purchase, finish, and re-derive the entitlement. Cancellation is not an
    /// error; `.pending` (ask-to-buy) resolves later via `Transaction.updates`.
    func purchase(_ product: StoreKit.Product) async throws {
        purchasing = true
        defer { purchasing = false }
        let result = try await product.purchase()
        if case .success(let verification) = result,
           case .verified(let transaction) = verification {
            await transaction.finish()
        }
        await refreshEntitlement()
    }

    /// "購入を復元" — required by App Review for any paid unlock.
    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
        await loadProducts()
    }
}
