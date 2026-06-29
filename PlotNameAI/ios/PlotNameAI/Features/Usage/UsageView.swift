import SwiftUI

// MARK: - UsageView

/// クレジットの残量と消費履歴を表示する。
struct UsageView: View {

    @Environment(UsageService.self) private var usage
    @Environment(BillingService.self) private var billing

    var body: some View {
        List {
            Section("プラン") {
                LabeledContent("現在のプラン", value: billing.currentPlan.displayName)
                LabeledContent("月額", value: billing.currentPlan.priceLabel)
            }

            Section("クレジット") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("残り \(usage.remainingCredits) / \(usage.monthlyAllowance)")
                            .font(.headline)
                        Spacer()
                    }
                    ProgressView(
                        value: Double(usage.remainingCredits),
                        total: Double(max(1, usage.monthlyAllowance))
                    )
                }
                .padding(.vertical, 4)
            }

            Section("履歴") {
                if usage.ledger.isEmpty {
                    Text("まだ消費履歴がありません。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(usage.ledger) { entry in
                        LedgerRow(entry: entry)
                    }
                }
            }
        }
        .navigationTitle("使用状況")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - LedgerRow

private struct LedgerRow: View {
    let entry: UsageLedgerEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.note.isEmpty ? (entry.stage?.displayName ?? "クレジット操作") : entry.note)
                    .font(.subheadline)
                Text(entry.timestamp, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.creditsDelta >= 0 ? "+\(entry.creditsDelta)" : "\(entry.creditsDelta)")
                .font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(entry.creditsDelta >= 0 ? .green : .red)
        }
    }
}

#Preview {
    NavigationStack {
        UsageView()
    }
    .environmentForPreview()
}
