import Foundation
import StoreKit

// MARK: - ProductID

/// App Store Connect / Products.storekit と一致させる正準のプロダクトID群。
/// ここを唯一の定義箇所とし、文字列リテラルの散在を避ける。
enum ProductID {

    // サブスクリプション（月額）
    static let plusMonthly = "com.plotname.ai.plus.monthly"
    static let proMonthly = "com.plotname.ai.pro.monthly"
    static let studioMonthly = "com.plotname.ai.studio.monthly"

    // サブスクリプション（年額）
    static let plusYearly = "com.plotname.ai.plus.yearly"
    static let proYearly = "com.plotname.ai.pro.yearly"
    static let studioYearly = "com.plotname.ai.studio.yearly"

    // 消耗型（クレジットパック）
    static let creditsSmall = "com.plotname.ai.credits.small"    // 100
    static let creditsMedium = "com.plotname.ai.credits.medium"  // 300
    static let creditsLarge = "com.plotname.ai.credits.large"    // 900
    static let creditsStudio = "com.plotname.ai.credits.studio"  // 3500

    /// 全サブスクリプションID。
    static let allSubscriptions: [String] = [
        plusMonthly, plusYearly,
        proMonthly, proYearly,
        studioMonthly, studioYearly,
    ]

    /// 全クレジットパックID。
    static let allCreditPacks: [String] = [
        creditsSmall, creditsMedium, creditsLarge, creditsStudio,
    ]

    /// ロード対象の全プロダクトID。
    static var all: [String] { allSubscriptions + allCreditPacks }

    /// サブスクリプションのプロダクトIDを対応プランへ変換する（非該当は nil）。
    static func plan(for productID: String) -> Plan? {
        switch productID {
        case plusMonthly, plusYearly: return .plus
        case proMonthly, proYearly: return .pro
        case studioMonthly, studioYearly: return .studio
        default: return nil
        }
    }

    /// 消耗型のプロダクトIDを付与クレジット数へ変換する（非該当は nil）。
    static func credits(for productID: String) -> Int? {
        switch productID {
        case creditsSmall: return 100
        case creditsMedium: return 300
        case creditsLarge: return 900
        case creditsStudio: return 3500
        default: return nil
        }
    }

    /// プランと請求期間からサブスクリプションのプロダクトIDを返す（Free は nil）。
    static func subscriptionID(for plan: Plan, yearly: Bool) -> String? {
        switch plan {
        case .free: return nil
        case .plus: return yearly ? plusYearly : plusMonthly
        case .pro: return yearly ? proYearly : proMonthly
        case .studio: return yearly ? studioYearly : studioMonthly
        }
    }
}

// MARK: - PurchaseOutcome

/// StoreKit 購入呼び出しの結果（UI が後処理を分岐するために返す）。
enum PurchaseOutcome: Equatable {
    /// 検証済みトランザクションを課金状態へ反映した。
    case success
    /// ユーザーがキャンセルした（エラー表示は不要）。
    case cancelled
    /// 承認待ち（Ask to Buy 等）。成立後に Transaction.updates 経由で反映される。
    case pending
}

// MARK: - StoreServiceError

/// StoreService 固有のエラー。
enum StoreServiceError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "購入の検証に失敗しました。しばらくしてからもう一度お試しください。"
        }
    }
}

// MARK: - StoreService

/// StoreKit 2 による実購入を扱うサービス。
/// - 商品ロード（サブスクリプション6種＋クレジットパック4種）
/// - 購入・復元・`Transaction.updates` の監視
/// - 検証済みトランザクションを BillingService / UsageService へ反映
///
/// ストアに接続できない環境（プレビュー・ASC 未設定・オフライン）では
/// `storeAvailable` が false になり、ペイウォールは従来のローカル
/// シミュレーション（開発モード）で動作し続ける。
@Observable
@MainActor
final class StoreService {

    // MARK: Published state

    /// ロード済みのサブスクリプション商品（ティア昇順・月額→年額）。
    private(set) var subscriptions: [Product] = []

    /// ロード済みのクレジットパック（価格昇順）。
    private(set) var creditPacks: [Product] = []

    /// 商品ロードが成功したか。
    private(set) var isLoaded = false

    /// 商品ロードの失敗メッセージ（UI 表示用）。
    private(set) var loadError: String?

    /// 購入処理中か（ボタンの多重タップ防止用）。
    private(set) var isPurchasing = false

    /// 実ストアで購入可能な状態か。false ならペイウォールは開発モードで動く。
    var storeAvailable: Bool { isLoaded && !subscriptions.isEmpty }

    // MARK: Dependencies

    private let billing: BillingService
    private let usage: UsageService

    /// Transaction.updates の監視タスク（start() で一度だけ生成）。
    @ObservationIgnored
    private var updatesTask: Task<Void, Never>?

    init(billing: BillingService, usage: UsageService) {
        self.billing = billing
        self.usage = usage
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: Lifecycle

    /// アプリ起動時に一度だけ呼ぶ。トランザクション更新の監視を開始し、
    /// 商品ロードと現在のエンタイトルメント反映を行う。二重呼び出しは無視。
    func start() async {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            // 自動更新・Ask to Buy 承認・返金などはアプリ起動中いつでも届く。
            for await result in Transaction.updates {
                await self?.handle(updateResult: result)
            }
        }
        await loadProducts()
        await updateEntitlementFromCurrent()
    }

    // MARK: Products

    /// App Store から商品情報を取得する。失敗しても致命的ではない
    /// （storeAvailable が false のままになり、開発モードにフォールバックする）。
    func loadProducts() async {
        do {
            let products = try await Product.products(for: ProductID.all)
            subscriptions = products
                .filter { $0.type == .autoRenewable }
                .sorted(by: Self.subscriptionOrder)
            creditPacks = products
                .filter { $0.type == .consumable }
                .sorted { $0.price < $1.price }
            isLoaded = true
            loadError = nil
        } catch {
            isLoaded = false
            loadError = "商品情報を取得できませんでした: \(error.localizedDescription)"
        }
    }

    /// 指定プラン・請求期間のサブスクリプション商品を返す。
    func subscriptionProduct(for plan: Plan, yearly: Bool) -> Product? {
        guard let id = ProductID.subscriptionID(for: plan, yearly: yearly) else { return nil }
        return subscriptions.first { $0.id == id }
    }

    // MARK: Purchase

    /// 商品を購入し、検証済みトランザクションを課金状態へ反映する。
    /// キャンセル・承認待ちはエラーにせず PurchaseOutcome で返す。
    @discardableResult
    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        // 多重実行防止（UI 側でも無効化するが念のため）。
        guard !isPurchasing else { return .cancelled }
        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            apply(transaction)
            await transaction.finish()
            return .success
        case .userCancelled:
            return .cancelled
        case .pending:
            // Ask to Buy など。承認後に Transaction.updates 経由で反映される。
            return .pending
        @unknown default:
            return .cancelled
        }
    }

    /// App Store と同期して購入を復元し、エンタイトルメントを再導出する。
    func restorePurchases() async {
        // sync は App Store サインインを促すことがある。失敗は無視して再導出に進む。
        try? await AppStore.sync()
        if !isLoaded {
            // 起動時にオフラインだった場合など、復元を機に商品ロードを再試行する。
            await loadProducts()
        }
        await updateEntitlementFromCurrent()
    }

    // MARK: Entitlements

    /// 現在有効なエンタイトルメントを走査し、最上位のプラン
    /// （studio > pro > plus）を適用する。有効なサブスクリプションが
    /// 無ければ Free。ただしストア未接続時（プレビュー・開発モード）は
    /// ローカルシミュレーションの状態を壊さないため降格しない。
    func updateEntitlementFromCurrent() async {
        // スクショ撮影モードでは AppEnvironment が設定した Pro を維持する。
        if ProcessInfo.processInfo.arguments.contains("-screenshotMode") { return }

        var best: Plan?
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard transaction.productType == .autoRenewable,
                  transaction.revocationDate == nil,
                  let plan = ProductID.plan(for: transaction.productID)
            else { continue }
            if Self.tier(of: plan) > Self.tier(of: best ?? .free) {
                best = plan
            }
        }

        let resolved: Plan
        if let best {
            resolved = best
        } else if storeAvailable {
            resolved = .free
        } else {
            // ストア未接続: ローカル状態（開発モードでの購入シミュレーション）を維持。
            return
        }

        guard resolved != billing.currentPlan else { return }
        billing.setPlan(resolved)
        usage.updateAllowance(billing.entitlement.limits.monthlyCredits)
    }

    // MARK: Transaction updates

    /// Transaction.updates から届いた更新（自動更新・Ask to Buy 承認・返金など）を処理する。
    private func handle(updateResult result: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(result) else { return }

        if let credits = ProductID.credits(for: transaction.productID) {
            // 消耗型: 承認待ちが後から成立したケースなど。
            if transaction.revocationDate == nil {
                usage.grant(credits, note: "クレジットパック購入（\(transaction.productID)）")
            }
        } else {
            // サブスクリプション: 更新・変更・返金を現エンタイトルメントから再導出する。
            await updateEntitlementFromCurrent()
        }
        await transaction.finish()
    }

    // MARK: Helpers

    /// 署名検証。unverified はエラーとして扱う。
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreServiceError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    /// 検証済みトランザクションを課金状態へ反映する。
    private func apply(_ transaction: Transaction) {
        guard transaction.revocationDate == nil else { return }

        if let plan = ProductID.plan(for: transaction.productID) {
            // サブスクリプション: プランを切り替え、月間クレジット枠を更新。
            billing.setPlan(plan)
            usage.updateAllowance(billing.entitlement.limits.monthlyCredits)
        } else if let credits = ProductID.credits(for: transaction.productID) {
            // 消耗型: クレジットを台帳に付与。
            usage.grant(credits, note: "クレジットパック購入（\(transaction.productID)）")
        }
    }

    /// サブスクリプション商品の表示順（ティア昇順 → 月額を年額より先に）。
    private nonisolated static func subscriptionOrder(_ lhs: Product, _ rhs: Product) -> Bool {
        let lhsPlan = ProductID.plan(for: lhs.id) ?? .free
        let rhsPlan = ProductID.plan(for: rhs.id) ?? .free
        if lhsPlan != rhsPlan { return tier(of: lhsPlan) < tier(of: rhsPlan) }
        return lhs.subscription?.subscriptionPeriod.unit == .month
            && rhs.subscription?.subscriptionPeriod.unit == .year
    }

    /// プランの序列（free < plus < pro < studio）。
    private nonisolated static func tier(of plan: Plan) -> Int {
        Plan.allCases.firstIndex(of: plan) ?? 0
    }
}
