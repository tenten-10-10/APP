import Foundation

// MARK: - RewardError

/// リワード広告のエラー。
enum RewardError: LocalizedError {
    case notConfigured
    case notReady
    case dismissedWithoutReward

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "広告プロバイダーが設定されていません。"
        case .notReady:
            return "広告がまだ読み込まれていません。"
        case .dismissedWithoutReward:
            return "報酬を獲得する前に広告が閉じられました。"
        }
    }
}

// MARK: - RewardProviding

/// リワード広告の抽象。AdMob などが準拠する想定。
protocol RewardProviding: Sendable {
    /// リワード広告を視聴し、付与すべきクレジット数を返す。
    /// 最後まで視聴しなかった場合は throw。
    func showRewardedAd() async throws -> Int
}

// MARK: - MockRewardProvider

/// 視聴をシミュレートし、固定クレジットを返すモック（実 SDK 無し）。
struct MockRewardProvider: RewardProviding {
    /// 1回の視聴で付与するクレジット。
    let creditsPerReward: Int

    init(creditsPerReward: Int = 1) {
        self.creditsPerReward = creditsPerReward
    }

    func showRewardedAd() async throws -> Int {
        // 広告視聴の演出（数秒）。
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        return creditsPerReward
    }
}

// MARK: - AdMobRewardProvider (STUB)

/// Google Mobile Ads（AdMob）を使う本番プロバイダーのスタブ。
///
/// 実装メモ（将来）:
/// - `GADRewardedAd.load(withAdUnitID:request:)` で事前ロードし、
///   `present(fromRootViewController:userDidEarnRewardHandler:)` を continuation でラップする。
/// - AdMob SDK（GoogleMobileAds）を SPM/CocoaPods で追加し、Info.plist に GADApplicationIdentifier を設定（Xcodeで要確認）。
struct AdMobRewardProvider: RewardProviding {
    func showRewardedAd() async throws -> Int {
        // TODO: GADRewardedAd を用いた実装に差し替える。
        throw RewardError.notConfigured
    }
}

// MARK: - RewardService

/// リワード広告を視聴してクレジットを付与する @Observable サービス。
/// 付与は既存の UsageService.grant 経由で行い、台帳に記録される。
@Observable
@MainActor
final class RewardService {

    /// 視聴処理中フラグ。
    private(set) var isPresenting = false

    /// 直近のエラーメッセージ（UI 表示用）。
    var errorMessage: String?

    private let provider: RewardProviding
    private let usage: UsageService

    /// - Parameters:
    ///   - provider: 広告プロバイダー。既定は Mock。
    ///   - usage: クレジットを付与する UsageService。
    init(provider: RewardProviding = MockRewardProvider(), usage: UsageService) {
        self.provider = provider
        self.usage = usage
    }

    /// 広告を視聴し、報酬クレジットを付与する。成功時は付与数を返す。
    @discardableResult
    func watchAndGrant() async -> Int {
        guard !isPresenting else { return 0 }
        isPresenting = true
        errorMessage = nil
        defer { isPresenting = false }
        do {
            let credits = try await provider.showRewardedAd()
            usage.grant(credits, note: "リワード広告視聴ボーナス")
            return credits
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return 0
        }
    }
}
