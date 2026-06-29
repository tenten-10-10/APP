import SwiftUI

// MARK: - PanelInspectorView

/// 選択中のコマを編集するインスペクタ。変更は ProjectStore に保存する。
struct PanelInspectorView: View {

    /// 編集対象のコマ（初期値）。
    let panel: PanelSpec
    let projectID: UUID

    @Environment(ProjectStore.self) private var store

    // 編集用ローカル状態。
    @State private var description: String = ""
    @State private var dialogue: String = ""
    @State private var sfx: String = ""
    @State private var shot: String = ""
    @State private var camera: String = ""
    @State private var emotion: String = ""

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
