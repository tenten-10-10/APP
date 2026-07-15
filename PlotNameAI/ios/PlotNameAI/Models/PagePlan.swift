import Foundation

// MARK: - PagePlan

/// 1ページ分の設計図。フェーズと結びつき、ページの目的・感情・引きを定義する。
struct PagePlan: Codable, Identifiable, Hashable {
    /// pageNumber を識別子に使う。
    var id: Int { pageNumber }

    var pageNumber: Int
    var phase: Int                 // 所属フェーズ番号 1...13
    var pageGoal: String
    var readerEmotion: String
    var turningPoint: Bool
    var panelCount: Int
    var lastPanelHook: String      // 最終コマの引き
    var dialogueDensity: Density
    var visualDensity: Density
    var whyThisPageExists: String

    init(
        pageNumber: Int,
        phase: Int,
        pageGoal: String,
        readerEmotion: String,
        turningPoint: Bool = false,
        panelCount: Int,
        lastPanelHook: String,
        dialogueDensity: Density = .medium,
        visualDensity: Density = .medium,
        whyThisPageExists: String
    ) {
        self.pageNumber = pageNumber
        self.phase = phase
        self.pageGoal = pageGoal
        self.readerEmotion = readerEmotion
        self.turningPoint = turningPoint
        self.panelCount = panelCount
        self.lastPanelHook = lastPanelHook
        self.dialogueDensity = dialogueDensity
        self.visualDensity = visualDensity
        self.whyThisPageExists = whyThisPageExists
    }

    /// 対応する Phase 列挙。
    var phaseEnum: Phase? { Phase(rawValue: phase) }
}
