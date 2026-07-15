import Foundation

// MARK: - GenerationStage

/// FABLE パイプラインの各ステージ。
enum GenerationStage: String, Codable, CaseIterable, Identifiable {
    case classifyGenre   // ジャンル分類
    case generatePhases  // 13フェーズ
    case generatePagePlan // 35ページプラン
    case generateLayout  // コマ割り
    case generateDialogue // セリフ
    case critique        // 批評
    case safetyCheck     // 安全性チェック

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classifyGenre: return "ジャンル分類"
        case .generatePhases: return "13フェーズ構成"
        case .generatePagePlan: return "ページプラン"
        case .generateLayout: return "コマ割り"
        case .generateDialogue: return "セリフ生成"
        case .critique: return "批評・調整"
        case .safetyCheck: return "安全性チェック"
        }
    }

    /// 表示順。
    var order: Int {
        switch self {
        case .classifyGenre: return 0
        case .generatePhases: return 1
        case .generatePagePlan: return 2
        case .generateLayout: return 3
        case .generateDialogue: return 4
        case .critique: return 5
        case .safetyCheck: return 6
        }
    }
}

// MARK: - GenerationJob

/// 生成ジョブの進捗を表す。
struct GenerationJob: Codable, Identifiable, Hashable {
    var id: UUID
    var projectId: UUID
    var stage: GenerationStage
    var progress: Double          // 0.0...1.0（全体進捗）
    var message: String
    var isFinished: Bool
    var startedAt: Date
    var finishedAt: Date?

    init(
        id: UUID = UUID(),
        projectId: UUID,
        stage: GenerationStage = .classifyGenre,
        progress: Double = 0,
        message: String = "",
        isFinished: Bool = false,
        startedAt: Date = .now,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.stage = stage
        self.progress = progress
        self.message = message
        self.isFinished = isFinished
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}
