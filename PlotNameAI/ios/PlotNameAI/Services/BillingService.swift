import Foundation

// MARK: - BillingService

/// プラン・エンタイトルメントの管理と機能ゲーティング。
/// 実際の課金処理は StoreKit2 で行う想定（ここではローカル状態のみ）。
@Observable
final class BillingService {

    /// 現在のプラン。
    private(set) var currentPlan: Plan

    /// 現在のエンタイトルメント。
    private(set) var entitlement: SubscriptionEntitlement

    /// ペイウォールを表示すべきトリガー（呼び出し側が監視）。
    var paywallTrigger: PaywallTrigger?

    init(plan: Plan = .free) {
        self.currentPlan = plan
        self.entitlement = SubscriptionEntitlement.defaultEntitlement(for: plan)
    }

    // MARK: Feature gating

    /// 機能が利用可能か。
    func isUnlocked(_ feature: Feature) -> Bool {
        entitlement.has(feature)
    }

    /// 機能を要求する。使えない場合はペイウォールトリガーを立てて false を返す。
    @discardableResult
    func requireFeature(_ feature: Feature) -> Bool {
        if isUnlocked(feature) { return true }
        paywallTrigger = PaywallTrigger(feature: feature, requiredPlan: minimumPlan(for: feature))
        return false
    }

    /// 指定機能を解放する最小プランを返す。
    func minimumPlan(for feature: Feature) -> Plan {
        for plan in Plan.allCases where SubscriptionEntitlement.defaultEntitlement(for: plan).has(feature) {
            return plan
        }
        return .studio
    }

    // MARK: Project limits

    /// 現在のプランで新規プロジェクトを作成できるか。
    func canCreateProject(currentCount: Int) -> Bool {
        let limit = entitlement.limits.maxProjects
        return limit < 0 || currentCount < limit
    }

    // MARK: Purchase (mock)

    /// プランを変更する（StoreKit 購入完了時に呼ぶ想定）。
    func setPlan(_ plan: Plan) {
        currentPlan = plan
        entitlement = SubscriptionEntitlement.defaultEntitlement(for: plan)
        paywallTrigger = nil
    }

    /// ペイウォールを閉じる。
    func dismissPaywall() {
        paywallTrigger = nil
    }
}

// MARK: - PaywallTrigger

/// ペイウォールを開く理由。
struct PaywallTrigger: Identifiable, Equatable {
    let id = UUID()
    let feature: Feature
    let requiredPlan: Plan
}
