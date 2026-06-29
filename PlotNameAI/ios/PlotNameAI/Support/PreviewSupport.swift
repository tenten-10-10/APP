import SwiftUI

// MARK: - Preview environment injection

extension View {
    /// プレビュー用に AppEnvironment と各サービスを一括注入する。
    @MainActor
    func environmentForPreview(plan: Plan = .pro) -> some View {
        let env = AppEnvironment()
        env.billing.setPlan(plan)
        env.usage.updateAllowance(env.billing.entitlement.limits.monthlyCredits)
        return self
            .environment(env)
            .environment(env.store)
            .environment(env.billing)
            .environment(env.usage)
            .environment(env.generation)
            .environment(env.safety)
            .environment(env.config)
    }
}
