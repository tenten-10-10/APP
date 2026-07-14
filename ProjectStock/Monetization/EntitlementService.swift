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

    /// Master switch for the タナミル チーム subscription UI (paywall gate on
    /// sharing + the Settings row). The hard-coded default is OFF because the
    /// subscription products don't exist in App Store Connect yet — an enabled
    /// paywall would show an empty price list and block sharing for everyone.
    /// Controlled REMOTELY via app-config.json (`teamPlanEnabled`), so once
    /// the ASC products are live it can be turned on without an app release
    /// (docs/MONETIZATION_PLAN_JA.md).
    static var teamPlanEnabled: Bool {
        RemoteConfig.shared.bool("teamPlanEnabled", default: false)
    }

    /// ハンディモード（連続バーコードスキャン）の公開キルスイッチ。既定 ON —
    /// ベータとして無料開放中。重大な不具合が出たら app-config.json の
    /// `handyEnabled: false` で即時に入口を隠せる。
    static var handyEnabled: Bool {
        RemoteConfig.shared.bool("handyEnabled", default: true)
    }

    /// ベータ終了後にハンディモードをチームプラン特典へ切り替えるフラグ。
    /// `handyPremium: true` を配信すると、以後は購読者のみ利用可（アプリ更新
    /// 不要）。既定 OFF = 無料ベータ。
    static var handyPremium: Bool {
        RemoteConfig.shared.bool("handyPremium", default: false)
    }

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
