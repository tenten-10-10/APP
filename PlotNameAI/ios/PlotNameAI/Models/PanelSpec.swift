import Foundation

// MARK: - PanelLayout

/// コマの相対座標とサイズ。すべて 0.0...1.0 のページ内比率。
struct PanelLayout: Codable, Hashable {
    var x: Double  // 左上 X（0...1）
    var y: Double  // 左上 Y（0...1）
    var w: Double  // 幅（0...1）
    var h: Double  // 高さ（0...1）

    init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

// MARK: - PanelLayouts

/// コマ割りテンプレート。座標は中立的な左上原点（LTR）で定義する。
/// マンガの右開き表現は描画側が X をミラーリングして行うため、
/// ここでは panel1 を左上に置く（ミラー後に右上＝読み始めになる）。
enum PanelLayouts {

    /// コマ数に応じた読みやすい矩形配置（0...1 比率）。
    static func rects(count: Int) -> [PanelLayout] {
        switch count {
        case ...1:
            return [PanelLayout(x: 0.05, y: 0.05, w: 0.90, h: 0.90)]
        case 2:
            return [
                PanelLayout(x: 0.05, y: 0.05, w: 0.90, h: 0.44),
                PanelLayout(x: 0.05, y: 0.51, w: 0.90, h: 0.44)
            ]
        case 3:
            return [
                PanelLayout(x: 0.05, y: 0.05, w: 0.90, h: 0.30),
                PanelLayout(x: 0.05, y: 0.37, w: 0.90, h: 0.30),
                PanelLayout(x: 0.05, y: 0.69, w: 0.90, h: 0.26)
            ]
        case 4:
            return [
                PanelLayout(x: 0.05, y: 0.05, w: 0.43, h: 0.44),  // 上段：読み始め（ミラーで右上）
                PanelLayout(x: 0.52, y: 0.05, w: 0.43, h: 0.44),  // 上段：次（ミラーで左上）
                PanelLayout(x: 0.05, y: 0.51, w: 0.43, h: 0.44),  // 下段：読み始め
                PanelLayout(x: 0.52, y: 0.51, w: 0.43, h: 0.44)   // 下段：次
            ]
        case 5:
            return [
                PanelLayout(x: 0.05, y: 0.05, w: 0.90, h: 0.26),  // 上段ワイド
                PanelLayout(x: 0.05, y: 0.34, w: 0.43, h: 0.28),  // 中段：読み始め
                PanelLayout(x: 0.52, y: 0.34, w: 0.43, h: 0.28),  // 中段：次
                PanelLayout(x: 0.05, y: 0.65, w: 0.43, h: 0.30),  // 下段：読み始め
                PanelLayout(x: 0.52, y: 0.65, w: 0.43, h: 0.30)   // 下段：次
            ]
        default: // 6 以上は 6 コマグリッド
            return [
                PanelLayout(x: 0.05, y: 0.05, w: 0.43, h: 0.28),
                PanelLayout(x: 0.52, y: 0.05, w: 0.43, h: 0.28),
                PanelLayout(x: 0.05, y: 0.36, w: 0.43, h: 0.28),
                PanelLayout(x: 0.52, y: 0.36, w: 0.43, h: 0.28),
                PanelLayout(x: 0.05, y: 0.67, w: 0.43, h: 0.28),
                PanelLayout(x: 0.52, y: 0.67, w: 0.43, h: 0.28)
            ]
        }
    }
}

// MARK: - PanelSpec

/// 1コマの仕様。レイアウト・カメラ・セリフ・画像プロンプトを含む。
struct PanelSpec: Codable, Identifiable, Hashable {
    var id: UUID
    var pageNumber: Int
    var panelNumber: Int
    var layout: PanelLayout
    var shot: String           // ショットサイズ（例: クローズアップ）
    var camera: String         // カメラアングル（例: あおり）
    var description: String     // コマの内容
    var characters: [String]
    var dialogue: String
    var sfx: String            // 効果音・描き文字
    var emotion: String
    var imagePrompt: String

    init(
        id: UUID = UUID(),
        pageNumber: Int,
        panelNumber: Int,
        layout: PanelLayout,
        shot: String,
        camera: String,
        description: String,
        characters: [String] = [],
        dialogue: String = "",
        sfx: String = "",
        emotion: String = "",
        imagePrompt: String = ""
    ) {
        self.id = id
        self.pageNumber = pageNumber
        self.panelNumber = panelNumber
        self.layout = layout
        self.shot = shot
        self.camera = camera
        self.description = description
        self.characters = characters
        self.dialogue = dialogue
        self.sfx = sfx
        self.emotion = emotion
        self.imagePrompt = imagePrompt
    }
}
