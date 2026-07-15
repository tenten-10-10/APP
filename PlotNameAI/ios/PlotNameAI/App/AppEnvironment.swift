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
    let auth: AuthService
    let reward: RewardService
    let purchases: StoreService

    /// - Parameter store: 永続化バックエンドを差し替えたストア。
    ///   nil の場合はファイル永続化の既定ストアを使う（プレビュー・テスト用）。
    ///   端末では PlotNameAIApp が SwiftData 版を注入する。
    init(store: ProjectStore? = nil) {
        let config = AppConfig()
        let store = store ?? ProjectStore()
        let billing = BillingService(plan: .free)
        // スクショ撮影モード（fastlane snapshot）: キャンバス等を撮るため Pro 相当で起動する。
        if ProcessInfo.processInfo.arguments.contains("-screenshotMode") {
            billing.setPlan(.pro)
        }
        let usage = UsageService(monthlyAllowance: billing.entitlement.limits.monthlyCredits)
        let safety = SafetyService()

        self.config = config
        self.store = store
        self.billing = billing
        self.usage = usage
        self.safety = safety
        self.generation = GenerationService(store: store, usage: usage, config: config)
        // 認証は既定で Mock（自動サインイン）。リワードは Usage にクレジット付与する。
        self.auth = AuthService()
        self.reward = RewardService(usage: usage)
        // StoreKit 2 の実購入。監視・商品ロードはアプリ起動時の start() で行う。
        self.purchases = StoreService(billing: billing, usage: usage)
    }

    /// プレビュー・テスト用の軽量初期化。
    static func preview() -> AppEnvironment {
        AppEnvironment()
    }
}
