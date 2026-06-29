import SwiftUI

// MARK: - PagePlanView

/// 35ページのプランを縦リストで一覧。ターニングポイントを強調表示。
struct PagePlanView: View {

    @Environment(ProjectStore.self) private var store
    /// iPad では中央→右カラム連携のためページ選択を共有する。
    @Binding var selectedPage: Int

    init(selectedPage: Binding<Int> = .constant(1)) {
        self._selectedPage = selectedPage
    }

    private var plans: [PagePlan] {
        (store.selectedBundle?.pagePlans ?? []).sorted { $0.pageNumber < $1.pageNumber }
    }

    /// List の単一選択は Optional バインディングを要求するため橋渡しする。
    private var selectionBinding: Binding<Int?> {
        Binding(
            get: { selectedPage },
            set: { if let value = $0 { selectedPage = value } }
        )
    }

    var body: some View {
        List(selection: selectionBinding) {
            if plans.isEmpty {
                ContentUnavailableView(
                    "ページ未生成",
                    systemImage: "doc.on.doc",
                    description: Text("プロジェクトを生成するとページプランが表示されます。")
                )
            } else {
                ForEach(plans) { plan in
                    PagePlanRow(plan: plan)
                        .tag(plan.pageNumber)
                }
            }
        }
        .navigationTitle("ページプラン")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PagePlanRow

private struct PagePlanRow: View {
    let plan: PagePlan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("P.\(plan.pageNumber)")
                    .font(.headline.monospacedDigit())
                if let phase = plan.phaseEnum {
                    Chip(text: "\(phase.number) \(phase.phaseName)", color: Theme.color(forPhase: phase.number))
                }
                if plan.turningPoint {
                    Label("転換", systemImage: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text("\(plan.panelCount)コマ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(plan.pageGoal)
                .font(.subheadline)

            Text("引き：\(plan.lastPanelHook)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Chip(text: "感情:\(plan.readerEmotion)", color: .purple)
                Chip(text: "台詞:\(plan.dialogueDensity.displayName)", color: Theme.color(forDensity: plan.dialogueDensity))
                Chip(text: "画面:\(plan.visualDensity.displayName)", color: Theme.color(forDensity: plan.visualDensity))
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        PagePlanView()
    }
    .environmentForPreview()
}
