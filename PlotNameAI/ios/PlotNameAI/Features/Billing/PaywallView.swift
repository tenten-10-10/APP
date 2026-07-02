import StoreKit
import SwiftUI

// MARK: - PaywallView

/// 4ティアのプランを提示するペイウォール。
/// ストア接続時（storeAvailable）は StoreKit 2 の実商品で購入し、
/// 未接続時（プレビュー・ASC 未設定）は従来のローカルシミュレーションで動く。
struct PaywallView: View {

    /// 表示のきっかけ（特定機能要求）。任意。
    var trigger: PaywallTrigger?

    @Environment(\.dismiss) private var dismiss
    @Environment(BillingService.self) private var billing
    @Environment(UsageService.self) private var usage
    @Environment(StoreService.self) private var purchases

    @State private var selected: Plan = .pro
    /// 年額プランを表示・購入するか（ストア接続時のみ切り替え可能）。
    @State private var isYearly = false
    @State private var isPurchasing = false
    @State private var isRestoring = false
    /// 購入・復元のエラー（インライン表示）。
    @State private var purchaseError: String?
    /// 承認待ちや復元完了などの情報メッセージ。
    @State private var infoMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let trigger {
                        triggerBanner(trigger)
                    }

                    if purchases.storeAvailable {
                        billingPeriodPicker
                    }

                    ForEach(Plan.allCases) { plan in
                        PlanCard(
                            plan: plan,
                            priceText: priceText(for: plan),
                            isCurrent: plan == billing.currentPlan,
                            isSelected: plan == selected
                        )
                        .onTapGesture { selected = plan }
                    }

                    creditPacksSection

                    // 無料プラン向け: 広告視聴で生成枠を増やす導線。
                    if billing.currentPlan == .free {
                        VStack(spacing: 8) {
                            Text("今すぐ無料で枠を増やす")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            RewardButton()
                        }
                        .padding(.top, 4)
                    }

                    footer
                }
                .padding()
            }
            .navigationTitle("プラン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                purchaseBar
            }
            .task {
                // 起動時のロードに失敗していたら、ペイウォールを開いた機会に再試行する。
                if !purchases.isLoaded {
                    await purchases.loadProducts()
                }
            }
        }
    }

    // MARK: Trigger banner

    private func triggerBanner(_ trigger: PaywallTrigger) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.open.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("「\(trigger.feature.displayName)」を使うには \(trigger.requiredPlan.displayName) 以上が必要です")
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .onAppear {
            // 要求プランを既定選択にする。
            selected = trigger.requiredPlan == .free ? .pro : trigger.requiredPlan
        }
    }

    // MARK: Billing period

    private var billingPeriodPicker: some View {
        Picker("請求期間", selection: $isYearly) {
            Text("月額").tag(false)
            Text("年額（約2か月分お得）").tag(true)
        }
        .pickerStyle(.segmented)
    }

    /// プランカードに表示する価格文字列。ストア接続時は実商品の現地価格。
    private func priceText(for plan: Plan) -> String {
        if plan == .free { return "無料" }
        if purchases.storeAvailable,
           let product = purchases.subscriptionProduct(for: plan, yearly: isYearly) {
            return product.displayPrice + (isYearly ? "/年" : "/月")
        }
        return plan.priceLabel
    }

    // MARK: Credit packs

    /// クレジット追加パック（消耗型4種）。ストア接続時は実購入、
    /// 未接続時は開発モードとしてローカル付与する。
    private var creditPacksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("クレジット追加パック")
                .font(.headline)
            Text("生成クレジットが足りないときに追加購入できます（買い切り・無期限）。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if purchases.storeAvailable {
                ForEach(purchases.creditPacks, id: \.id) { product in
                    CreditPackRow(
                        title: product.displayName,
                        credits: ProductID.credits(for: product.id) ?? 0,
                        priceLabel: product.displayPrice,
                        isDisabled: isPurchasing || isRestoring
                    ) {
                        Task { await purchaseCreditPack(product) }
                    }
                }
            } else {
                ForEach(CreditPackFallback.all) { pack in
                    CreditPackRow(
                        title: pack.title,
                        credits: pack.credits,
                        priceLabel: pack.priceLabel,
                        isDisabled: isPurchasing || isRestoring
                    ) {
                        // 開発モード: 実購入なしでクレジットを付与する。
                        usage.grant(pack.credits, note: "クレジットパック購入（開発モード）")
                        infoMessage = "\(pack.credits)クレジットを追加しました。"
                    }
                }
                Text("(開発モード: 購入シミュレーション)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func purchaseCreditPack(_ product: Product) async {
        purchaseError = nil
        infoMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await purchases.purchase(product) {
            case .success:
                infoMessage = "\(ProductID.credits(for: product.id) ?? 0)クレジットを追加しました。"
            case .pending:
                infoMessage = "購入は承認待ちです。承認されると自動的に反映されます。"
            case .cancelled:
                break
            }
        } catch {
            purchaseError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: Footer (復元・規約・自動更新の説明)

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                Task { await restore() }
            } label: {
                if isRestoring {
                    ProgressView()
                } else {
                    Text("購入を復元")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRestoring || isPurchasing)

            Text("サブスクリプションは、期間終了の24時間前までに解約しない限り自動的に更新され、更新前の24時間以内にApple IDへ料金が請求されます。購入後はApp Storeのアカウント設定からいつでも解約・プラン変更ができます。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("利用規約", destination: PaywallView.termsURL)
                Link("プライバシーポリシー", destination: PaywallView.privacyURL)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // TODO: 公開前に正式な規約・ポリシーページの URL に差し替える。
    private static let termsURL = URL(string: "https://github.com/tenten-10-10/APP")!
    private static let privacyURL = URL(string: "https://github.com/tenten-10-10/APP")!

    private func restore() async {
        purchaseError = nil
        infoMessage = nil
        isRestoring = true
        defer { isRestoring = false }
        await purchases.restorePurchases()
        infoMessage = purchases.storeAvailable
            ? "購入情報を確認しました。"
            : "ストアに接続できないため、復元できる購入はありません。"
    }

    // MARK: Purchase bar

    private var purchaseBar: some View {
        VStack(spacing: 8) {
            if let purchaseError {
                Text(purchaseError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            } else if let infoMessage {
                Text(infoMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await purchaseSelected() }
            } label: {
                HStack(spacing: 8) {
                    if isPurchasing {
                        ProgressView()
                    }
                    Text(buttonTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(purchaseDisabled)

            if purchases.storeAvailable {
                Text("いつでも解約できます。価格は税込です。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("(開発モード: 購入シミュレーション)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.bar)
    }

    private var buttonTitle: String {
        if selected == billing.currentPlan { return "現在のプラン" }
        if selected == .free {
            // 実ストアでは「解約」= App Store のサブスクリプション管理。
            return purchases.storeAvailable ? "解約はApp Storeの設定から" : "Freeに変更"
        }
        if purchases.storeAvailable {
            if let product = purchases.subscriptionProduct(for: selected, yearly: isYearly) {
                return "\(selected.displayName) を開始（\(product.displayPrice)\(isYearly ? "/年" : "/月")）"
            }
            return "\(selected.displayName) を開始"
        }
        return "\(selected.displayName) を開始（\(selected.priceLabel)）"
    }

    private var purchaseDisabled: Bool {
        if isPurchasing || isRestoring { return true }
        if selected == billing.currentPlan { return true }
        // 実ストアでは Free への変更（解約）は App Store 側で行うため無効。
        if purchases.storeAvailable && selected == .free { return true }
        return false
    }

    private func purchaseSelected() async {
        purchaseError = nil
        infoMessage = nil

        // ストア未接続（プレビュー・開発）: 従来通りローカルにプランを設定する。
        guard purchases.storeAvailable else {
            billing.setPlan(selected)
            usage.updateAllowance(billing.entitlement.limits.monthlyCredits)
            dismiss()
            return
        }

        guard selected != .free,
              let product = purchases.subscriptionProduct(for: selected, yearly: isYearly)
        else {
            purchaseError = "この商品は現在購入できません。"
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await purchases.purchase(product) {
            case .success:
                dismiss()
            case .pending:
                infoMessage = "購入は承認待ちです。承認されると自動的に反映されます。"
            case .cancelled:
                break
            }
        } catch {
            purchaseError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - PlanCard

private struct PlanCard: View {
    let plan: Plan
    let priceText: String
    let isCurrent: Bool
    let isSelected: Bool

    private var entitlement: SubscriptionEntitlement {
        SubscriptionEntitlement.defaultEntitlement(for: plan)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(plan.displayName)
                    .font(.title3.bold())
                if isCurrent {
                    Chip(text: "利用中", color: .green)
                }
                Spacer()
                Text(priceText)
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(entitlement.features) { feature in
                    Label(feature.displayName, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Label(projectLimitText, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("月\(entitlement.limits.monthlyCredits)クレジット", systemImage: "bolt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
    }

    private var projectLimitText: String {
        let limit = entitlement.limits.maxProjects
        return limit < 0 ? "無制限プロジェクト" : "プロジェクト \(limit)件まで"
    }
}

// MARK: - CreditPackRow

/// クレジットパック1件の購入行。
private struct CreditPackRow: View {
    let title: String
    let credits: Int
    let priceLabel: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label("\(title)（\(credits)クレジット）", systemImage: "bolt.badge.clock")
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                Text(priceLabel)
                    .font(.subheadline.bold())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .disabled(isDisabled)
    }
}

// MARK: - CreditPackFallback

/// ストア未接続時（開発モード）に表示するクレジットパックの静的定義。
/// 価格は Products.storekit の表示価格に合わせた参考値。
private struct CreditPackFallback: Identifiable {
    let id: String
    let title: String
    let credits: Int
    let priceLabel: String

    static let all: [CreditPackFallback] = [
        .init(id: ProductID.creditsSmall, title: "クレジット100", credits: 100, priceLabel: "¥480"),
        .init(id: ProductID.creditsMedium, title: "クレジット300", credits: 300, priceLabel: "¥1,200"),
        .init(id: ProductID.creditsLarge, title: "クレジット900", credits: 900, priceLabel: "¥3,000"),
        .init(id: ProductID.creditsStudio, title: "スタジオパック3500", credits: 3500, priceLabel: "¥9,800"),
    ]
}

#Preview {
    PaywallView(trigger: PaywallTrigger(feature: .ipadCanvas, requiredPlan: .pro))
        .environmentForPreview(plan: .free)
}

#Preview("ダーク") {
    PaywallView(trigger: PaywallTrigger(feature: .ipadCanvas, requiredPlan: .pro))
        .environmentForPreview(plan: .free)
        .preferredColorScheme(.dark)
}
