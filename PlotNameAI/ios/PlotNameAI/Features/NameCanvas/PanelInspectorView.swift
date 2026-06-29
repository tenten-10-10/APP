import SwiftUI

// MARK: - PanelInspectorView

/// 選択中のコマを編集するインスペクタ。変更は ProjectStore に保存する。
struct PanelInspectorView: View {

    /// 編集対象のコマ（初期値）。
    let panel: PanelSpec
    let projectID: UUID

    @Environment(ProjectStore.self) private var store
    @Environment(BillingService.self) private var billing
    @Environment(UsageService.self) private var usage
    @Environment(AppConfig.self) private var config

    // 編集用ローカル状態。
    @State private var description: String = ""
    @State private var dialogue: String = ""
    @State private var sfx: String = ""
    @State private var shot: String = ""
    @State private var camera: String = ""
    @State private var emotion: String = ""

    // ラフ生成の状態。
    @State private var isGeneratingRough = false
    @State private var roughError: String?

    /// ラフ画像 1 コマあたりの消費クレジット。
    private let roughCreditCost = 1

    private let shotOptions = ["ロング", "ミディアム", "バストアップ", "クローズアップ", "大ゴマ・ロング"]
    private let cameraOptions = ["水平", "あおり", "俯瞰", "主観"]

    var body: some View {
        Form {
            Section("コマ \(panel.panelNumber)（P.\(panel.pageNumber)）") {
                Picker("ショット", selection: $shot) {
                    ForEach(shotOptions, id: \.self) { Text($0).tag($0) }
                }
                Picker("カメラ", selection: $camera) {
                    ForEach(cameraOptions, id: \.self) { Text($0).tag($0) }
                }
                TextField("感情", text: $emotion)
            }

            Section("内容") {
                TextField("コマの説明", text: $description, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section("セリフ・効果音") {
                TextField("セリフ", text: $dialogue, axis: .vertical)
                    .lineLimit(1...3)
                TextField("効果音（SFX）", text: $sfx)
            }

            if !panel.imagePrompt.isEmpty {
                Section("画像プロンプト") {
                    Text(panel.imagePrompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: ラフ生成
            Section("ラフ画像") {
                // 既存のラフがあれば表示。
                if let rough = currentRough {
                    PanelRoughView(rough: rough)
                        .frame(maxWidth: 200)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Button {
                    generateRough()
                } label: {
                    HStack {
                        if isGeneratingRough {
                            ProgressView()
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                        Text(currentRough == nil ? "ラフ生成（\(roughCreditCost)クレジット）" : "ラフを作り直す（\(roughCreditCost)クレジット）")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isGeneratingRough)

                if let roughError {
                    Text(roughError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    Label("変更を保存", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear(perform: loadFromPanel)
        .onChange(of: panel.id) { loadFromPanel() }
    }

    // MARK: Rough

    /// ストア上の最新コマ（生成後の rough を即座に反映するため）。
    private var livePanel: PanelSpec {
        store.bundle(for: projectID)?
            .panels.first(where: { $0.id == panel.id }) ?? panel
    }

    private var currentRough: PanelRough? {
        livePanel.rough
    }

    /// ラフ生成を実行する。
    /// ゲート: 1) Pro 機能（.imageRoughGeneration）2) クレジット残量。
    private func generateRough() {
        roughError = nil

        // 1) 機能ゲート。ロック時はペイウォールを提示して終了。
        guard billing.requireFeature(.imageRoughGeneration) else { return }

        // 2) クレジットゲート。0 ならペイウォール／広告へ誘導。
        guard usage.canSpend(roughCreditCost) else {
            roughError = "クレジットが不足しています。広告視聴かプラン変更で枠を増やせます。"
            // 使用状況・ペイウォールへ誘導（ペイウォールには広告ボタンがある）。
            billing.requireFeature(.imageRoughGeneration)
            return
        }

        let targetPanel = livePanel
        let brief = makeRoughBrief()
        let provider = config.makeProvider()

        isGeneratingRough = true
        Task {
            defer { isGeneratingRough = false }
            do {
                let rough = try await provider.generatePanelRough(panel: targetPanel, brief: brief)
                // クレジット消費（生成成功後に確定）。
                usage.spend(
                    roughCreditCost,
                    projectId: projectID,
                    stage: nil,
                    note: "ラフ生成 P.\(targetPanel.pageNumber)-\(targetPanel.panelNumber)"
                )
                var updated = targetPanel
                updated.rough = rough
                store.updatePanel(updated, in: projectID)
            } catch {
                roughError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// 物語の文脈をブリーフに詰める。
    private func makeRoughBrief() -> PanelRoughBrief {
        let bundle = store.bundle(for: projectID)
        let phaseName = bundle?.pagePlan(panel.pageNumber)?.phaseEnum?.phaseName ?? "本編"
        return PanelRoughBrief(
            theme: bundle?.brief?.theme ?? "",
            protagonistName: bundle?.brief?.protagonist.name ?? (panel.characters.first ?? "主人公"),
            phaseName: phaseName
        )
    }

    // MARK: Sync

    private func loadFromPanel() {
        description = panel.description
        dialogue = panel.dialogue
        sfx = panel.sfx
        shot = panel.shot
        camera = panel.camera
        emotion = panel.emotion
    }

    private func save() {
        var updated = panel
        updated.description = description
        updated.dialogue = dialogue
        updated.sfx = sfx
        updated.shot = shot
        updated.camera = camera
        updated.emotion = emotion
        store.updatePanel(updated, in: projectID)
    }
}

#Preview {
    PanelInspectorView(
        panel: SampleData.bundle.panels(onPage: 1).first!,
        projectID: SampleData.projectID
    )
    .environmentForPreview()
}
