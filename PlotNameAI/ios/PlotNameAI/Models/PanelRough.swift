import Foundation

// MARK: - PanelRough

/// コマのラフ画像「記述子」。
/// 実画像ではなく、キャンバスが決定論的に描ける軽量スペックを保持する。
/// （MockAIProvider はオフラインで一貫した結果を返すため、SF Symbol 名＋
///  キャプション＋シード＋簡単な図形指定で「ラフ」を表現する。）
struct PanelRough: Codable, Hashable, Identifiable {

    var id: UUID
    /// 対象コマの ID。
    var panelId: UUID
    /// プレースホルダーに使う SF Symbol 名（例: "figure.run"）。
    var symbolName: String
    /// 短いキャプション（生成意図の要約）。
    var caption: String
    /// 決定論的シード（同じ入力からは同じラフ）。
    var seed: Int
    /// キャンバス描画用の簡易図形スペック。
    var shapes: [RoughShape]
    /// 生成日時。
    var createdAt: Date

    init(
        id: UUID = UUID(),
        panelId: UUID,
        symbolName: String,
        caption: String,
        seed: Int,
        shapes: [RoughShape] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.panelId = panelId
        self.symbolName = symbolName
        self.caption = caption
        self.seed = seed
        self.shapes = shapes
        self.createdAt = createdAt
    }
}

// MARK: - RoughShape

/// ラフ描画用の単純な図形（0...1 のコマ内相対座標）。
/// 実画像を持たないため、キャンバスはこの配列を線画として描く。
struct RoughShape: Codable, Hashable {

    enum Kind: String, Codable {
        case rectangle   // 背景・建物など
        case ellipse     // 顔・頭・玉
        case line        // 集中線・地面など
    }

    var kind: Kind
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    init(kind: Kind, x: Double, y: Double, w: Double, h: Double) {
        self.kind = kind
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}
