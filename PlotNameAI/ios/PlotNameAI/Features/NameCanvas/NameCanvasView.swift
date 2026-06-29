import SwiftUI

// MARK: - NameCanvasView

/// ネームキャンバス。ページを選んでコマ配置を確認・選択する。
/// iPad キャンバス編集は Pro 以上の機能としてゲートする。
struct NameCanvasView: View {

    let bundle: ProjectBundle
    @State var selectedPage: Int
    @Binding var selectedPanelID: PanelSpec.ID?

    @Environment(BillingService.self) private var billing
    @Environment(ProjectStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// 赤入れ（PencilKit）モード。
    @State private var isAnnotating = false

    private var pageCount: Int {
        max(bundle.pagePlans.count, bundle.project.pageCount)
    }

    /// iPad（regular 幅）でのみ赤入れを許可する。
    private var supportsAnnotation: Bool {
        horizontalSizeClass == .regular
    }

    /// 現在ページの赤入れデータ（ストアの最新を参照）。
    private var annotationData: Data {
        store.bundle(for: bundle.id)?.annotations[selectedPage] ?? Data()
    }

    /// 赤入れデータの読み書きバインディング（書き込みは ProjectStore へ永続化）。
    private var annotationBinding: Binding<Data> {
        Binding(
            get: { annotationData },
            set: { store.updateAnnotation($0, page: selectedPage, in: bundle.id) }
        )
    }

    private var currentPanels: [PanelSpec] {
        // ストアの最新束を参照（ラフ生成などの更新を反映）。
        (store.bundle(for: bundle.id) ?? bundle).panels(onPage: selectedPage)
    }

    private var currentPlan: PagePlan? {
        bundle.pagePlan(selectedPage)
    }

    var body: some View {
        VStack(spacing: 0) {
            pageHeader

            if billing.isUnlocked(.ipadCanvas) {
                ZStack {
                    PanelCanvasView(
                        panels: currentPanels,
                        pageNumber: selectedPage,
                        selectedPanelID: $selectedPanelID
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))

                    // 赤入れオーバーレイ（iPad のみ・有効時のみ操作可）。
                    if supportsAnnotation && (isAnnotating || !annotationData.isEmpty) {
                        AnnotationCanvasView(
                            drawingData: annotationBinding,
                            isActive: isAnnotating
                        )
                        .allowsHitTesting(isAnnotating)
                    }
                }

                if let panelID = selectedPanelID,
                   let panel = currentPanels.first(where: { $0.id == panelID }) {
                    PanelInspectorView(panel: panel, projectID: bundle.id)
                        .frame(maxHeight: 320)
                }
            } else {
                lockedState
            }
        }
        .navigationTitle("ネームキャンバス")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if supportsAnnotation && billing.isUnlocked(.ipadCanvas) {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAnnotating.toggle()
                    } label: {
                        Label("赤入れ", systemImage: isAnnotating ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                    }
                    .tint(isAnnotating ? .red : nil)
                }
                if !annotationData.isEmpty {
                    ToolbarItem(placement: .secondaryAction) {
                        Button(role: .destructive) {
                            store.updateAnnotation(Data(), page: selectedPage, in: bundle.id)
                        } label: {
                            Label("赤入れを消去", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .onAppear {
            // 選択ページに対応するコマが無ければ先頭ページへ。
            if currentPanels.isEmpty, let first = bundle.pagePlans.first {
                selectedPage = first.pageNumber
            }
        }
    }

    // MARK: Header

    private var pageHeader: some View {
        VStack(spacing: 6) {
            HStack {
                Button {
                    if selectedPage < pageCount { selectedPage += 1; selectedPanelID = nil }
                } label: {
                    Image(systemName: "chevron.left")  // 右開き: 「進む」は左矢印
                }
                .disabled(selectedPage >= pageCount)

                Spacer()
                Text("ページ \(selectedPage) / \(pageCount)")
                    .font(.headline.monospacedDigit())
                Spacer()

                Button {
                    if selectedPage > 1 { selectedPage -= 1; selectedPanelID = nil }
                } label: {
                    Image(systemName: "chevron.right")  // 右開き: 「戻る」は右矢印
                }
                .disabled(selectedPage <= 1)
            }
            .padding(.horizontal)

            if let plan = currentPlan {
                HStack(spacing: 8) {
                    if let phase = plan.phaseEnum {
                        Chip(text: "\(phase.number) \(phase.phaseName)",
                             color: Theme.color(forPhase: phase.number))
                    }
                    if plan.turningPoint {
                        Chip(text: "転換点", color: .orange)
                    }
                    Chip(text: "\(plan.panelCount)コマ", color: .gray)
                    Spacer()
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Locked

    private var lockedState: some View {
        VStack(spacing: 16) {
            // ロック中でもキャンバスのプレビューは見せる（編集不可）。
            PanelCanvasView(
                panels: currentPanels,
                pageNumber: selectedPage,
                selectedPanelID: .constant(nil)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(.ultraThinMaterial)
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.largeTitle)
                    Text("ネーム編集は Pro 以上の機能です")
                        .font(.headline)
                    Button("プランを見る") {
                        billing.requireFeature(.ipadCanvas)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    NavigationStack {
        NameCanvasView(
            bundle: SampleData.bundle,
            selectedPage: 1,
            selectedPanelID: .constant(nil)
        )
    }
    .environmentForPreview(plan: .pro)
}
