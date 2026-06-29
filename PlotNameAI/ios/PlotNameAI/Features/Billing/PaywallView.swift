import SwiftUI

// MARK: - PaywallView

/// 4ティアのプランを提示するペイウォール。
/// 実購入は StoreKit2 で行う想定（ここではローカルにプランを設定）。
struct PaywallView: View {

    /// 表示のきっかけ（特定機能要求）。任意。
    var trigger: PaywallTrigger?

    @Environment(\.dismiss) private var dismiss
    @Environment(BillingService.self) private var billing
    @Environment(UsageService.self) private var usage

    @State private var selected: Plan = .pro

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let trigger {
                        triggerBanner(trigger)
                    }

                    ForEach(Plan.allCases) { plan in
                        PlanCard(
                            plan: plan,
                            isCurrent: plan == billing.currentPlan,
                            isSelected: plan == selected
                        )
                        .onTapGesture { selected = plan }
                    }

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

    // MARK: Purchase bar

    private var purchaseBar: some View {
        VStack(spacing: 8) {
            Button {
                purchase()
            } label: {
                Text(buttonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected == billing.currentPlan)

            Text("いつでも解約できます。価格は税込です。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.bar)
    }

    private var buttonTitle: String {
        if selected == .free { return "Freeに変更" }
        if selected == billing.currentPlan { return "現在のプラン" }
        return "\(selected.displayName) を開始（\(selected.priceLabel)）"
    }

    private func purchase() {
        // 本番では StoreKit2 の購入完了後に setPlan を呼ぶ。
        billing.setPlan(selected)
        usage.updateAllowance(billing.entitlement.limits.monthlyCredits)
        dismiss()
    }
}

// MARK: - PlanCard

private struct PlanCard: View {
    let plan: Plan
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
                Text(plan.priceLabel)
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

#Preview {
    PaywallView(trigger: PaywallTrigger(feature: .ipadCanvas, requiredPlan: .pro))
        .environmentForPreview(plan: .free)
}
