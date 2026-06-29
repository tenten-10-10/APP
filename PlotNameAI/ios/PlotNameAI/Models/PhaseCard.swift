import Foundation

// MARK: - PhaseCard

/// 13フェーズ構造の各フェーズに対応するカード。
struct PhaseCard: Codable, Identifiable, Hashable {
    /// phaseNumber を識別子に使う（1...13）。
    var id: Int { phaseNumber }

    var phaseNumber: Int
    var phaseName: String
    var summary: String
    var function: String           // 物語上の役割
    var emotionalValue: Int        // 感情価（-5...+5 想定）
    var pages: [Int]               // このフェーズが占めるページ番号
    var mustShow: [String]         // 必ず描くべき要素
    var weaknessAlert: String?     // 弱点・注意点

    init(
        phaseNumber: Int,
        phaseName: String,
        summary: String,
        function: String,
        emotionalValue: Int,
        pages: [Int],
        mustShow: [String],
        weaknessAlert: String? = nil
    ) {
        self.phaseNumber = phaseNumber
        self.phaseName = phaseName
        self.summary = summary
        self.function = function
        self.emotionalValue = emotionalValue
        self.pages = pages
        self.mustShow = mustShow
        self.weaknessAlert = weaknessAlert
    }

    /// 対応する Phase 列挙（範囲外なら nil）。
    var phase: Phase? { Phase(rawValue: phaseNumber) }
}
