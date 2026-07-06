import SwiftUI
import StoreKit

/// タナミル チーム subscription paywall. Shown when a user without an active
/// subscription tries to START sharing a project. Includes everything App
/// Review requires for auto-renewable subscriptions: localized price from
/// StoreKit, auto-renewal disclosure, restore button, offer-code redemption,
/// and links to the Terms of Use (Apple standard EULA) and privacy policy.
struct PaywallView: View {
    @EnvironmentObject private var entitlements: EntitlementService
    @Environment(\.dismiss) private var dismiss
    @State private var showingRedemption = false
    @State private var error: PresentableError?

    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(NSLocalizedString("タナミル チーム", comment: ""), systemImage: "person.2.fill")
                            .font(.title3.weight(.bold))
                            .foregroundColor(Brand.primary)
                        Text(NSLocalizedString("プロジェクトを家族・チームと共有して、同じ在庫を一緒に管理できるようになります。", comment: ""))
                            .font(.subheadline)
                        featureRow("person.crop.circle.badge.plus", NSLocalizedString("招待リンクを送るだけでメンバーを追加", comment: ""))
                        featureRow("arrow.triangle.2.circlepath.icloud", NSLocalizedString("入出庫・貸出・棚卸しが全員に自動で反映", comment: ""))
                        featureRow("eye", NSLocalizedString("メンバーごとに「編集可 / 閲覧のみ」を設定", comment: ""))
                        featureRow("gift", NSLocalizedString("参加する側は無料（課金は共有するオーナーのみ）", comment: ""))
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    if entitlements.products.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(NSLocalizedString("価格を読み込んでいます…", comment: ""))
                                .font(.footnote).foregroundColor(.secondary)
                        }
                    }
                    ForEach(entitlements.products, id: \.id) { product in
                        Button {
                            Task {
                                do { try await entitlements.purchase(product) }
                                catch { self.error = PresentableError(AppError.underlying(error.localizedDescription)) }
                                if entitlements.hasTeamFeatures { dismiss() }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(product.displayName.isEmpty ? product.id : product.displayName)
                                        .font(.body.weight(.semibold))
                                    if let intro = product.subscription?.introductoryOffer,
                                       intro.paymentMode == .freeTrial {
                                        Text(String(format: NSLocalizedString("%@ 無料でお試し", comment: ""), Self.periodText(intro.period)))
                                            .font(.caption).foregroundColor(.green)
                                    }
                                }
                                Spacer()
                                Text(product.displayPrice).font(.body.weight(.semibold))
                            }
                        }
                        .disabled(entitlements.purchasing)
                    }
                } footer: {
                    Text(NSLocalizedString("サブスクリプションは期間終了の24時間前までに解約しない限り自動更新されます。購入後は「設定 > Apple ID > サブスクリプション」からいつでも解約できます。", comment: ""))
                        .font(.caption2)
                }

                Section {
                    Button {
                        showingRedemption = true
                    } label: {
                        Label(NSLocalizedString("コードを使う（招待コードをお持ちの方）", comment: ""), systemImage: "ticket")
                    }
                    Button {
                        Task { await entitlements.restore(); if entitlements.hasTeamFeatures { dismiss() } }
                    } label: {
                        Label(NSLocalizedString("購入を復元", comment: ""), systemImage: "arrow.clockwise")
                    }
                }

                Section {
                    Link(NSLocalizedString("利用規約", comment: ""),
                         destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    Link(NSLocalizedString("プライバシーポリシー", comment: ""),
                         destination: URL(string: "https://tenten-10-10.github.io/APP/privacy.html")!)
                }
                .font(.footnote)
            }
            .navigationTitle(NSLocalizedString("チーム共有", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("閉じる", comment: "")) { dismiss() }
                }
            }
            .errorAlert($error)
            .onAppear { Task { await entitlements.loadProducts() } }
            .background(redemptionPresenter)
        }
    }

    /// "2週間" 等の期間表示。StoreKit 2 の SubscriptionPeriod に
    /// localizedDescription は無いため自前で整形する。
    private static func periodText(_ period: StoreKit.Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day:   return String(format: NSLocalizedString("%d日間", comment: ""), period.value)
        case .week:  return String(format: NSLocalizedString("%d週間", comment: ""), period.value)
        case .month: return String(format: NSLocalizedString("%dヶ月", comment: ""), period.value)
        case .year:  return String(format: NSLocalizedString("%d年", comment: ""), period.value)
        @unknown default: return "\(period.value)"
        }
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(Brand.primary).frame(width: 22)
            Text(text).font(.footnote)
        }
    }

    /// Offer-code redemption: iOS 16+ has the SwiftUI modifier; on iOS 15 fall
    /// back to the StoreKit 1 sheet (the redeemed subscription still arrives
    /// through Transaction.updates either way).
    @ViewBuilder private var redemptionPresenter: some View {
        if #available(iOS 16.0, *) {
            Color.clear.offerCodeRedemption(isPresented: $showingRedemption) { _ in
                Task { await entitlements.refreshEntitlement(); if entitlements.hasTeamFeatures { dismiss() } }
            }
        } else {
            Color.clear.onChange(of: showingRedemption) { show in
                if show {
                    SKPaymentQueue.default().presentCodeRedemptionSheet()
                    showingRedemption = false
                }
            }
        }
    }
}
