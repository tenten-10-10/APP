import SwiftUI

// MARK: - RewardButton

/// 「広告を見て生成枠を増やす」ボタン。
/// 無料プランのユーザーに向けて、リワード広告視聴でクレジットを付与する導線。
/// 視聴成功時は付与クレジット数を onGranted で通知する。
struct RewardButton: View {

    @Environment(RewardService.self) private var reward
    @Environment(BillingService.self) private var billing

    /// 無料プラン以外でも表示するか（既定は無料のみ）。
    var freeOnly: Bool = true
    /// 付与成功時のコールバック（任意）。
    var onGranted: ((Int) -> Void)? = nil

    var body: some View {
        if !freeOnly || billing.currentPlan == .free {
            VStack(spacing: 6) {
                Button {
                    Task {
                        let credits = await reward.watchAndGrant()
                        if credits > 0 { onGranted?(credits) }
                    }
                } label: {
                    HStack {
                        if reward.isPresenting {
                            ProgressView()
                        } else {
                            Image(systemName: "play.rectangle.fill")
                        }
                        Text(reward.isPresenting ? "広告を再生中…" : "広告を見て生成枠を増やす")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(reward.isPresenting)

                if let error = reward.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

#Preview {
    RewardButton()
        .padding()
        .environmentForPreview(plan: .free)
}
