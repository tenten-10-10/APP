import Foundation
import SwiftUI

// MARK: - AppEnvironment

/// アプリ全体で共有するサービス群をまとめた合成ルート。
/// 各サービスは @Observable。View へは @Environment 経由で配布する。
@Observable
@MainActor
final class AppEnvironment {

    let config: AppConfig
    let store: ProjectStore
    let usage: UsageService
    let billing: BillingService
    let safety: SafetyService
    let generation: GenerationService

    init() {
        let config = AppConfig()
        let store = ProjectStore()
        let billing = BillingService(plan: .free)
        let usage = UsageService(monthlyAllowance: billing.entitlement.limits.monthlyCredits)
        let safety = SafetyService()

        self.config = config
        self.store = store
        self.billing = billing
        self.usage = usage
        self.safety = safety
        self.generation = GenerationService(store: store, usage: usage, config: config)
    }

    /// プレビュー・テスト用の軽量初期化。
    static func preview() -> AppEnvironment {
        AppEnvironment()
    }
}
