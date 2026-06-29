import Foundation

// MARK: - AIProviderError

enum AIProviderError: LocalizedError {
    case notConfigured
    case safetyViolation(reason: String)
    case invalidInput(reason: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "このプロバイダーは設定されていません（APIキー未設定）。"
        case .safetyViolation(let reason):
            return "安全性チェックに抵触しました: \(reason)"
        case .invalidInput(let reason):
            return "入力が不正です: \(reason)"
        }
    }
}

// MARK: - CritiqueResult

/// 批評ステージの結果。
struct CritiqueResult: Codable, Hashable {
    var score: Int          // 0...100
    var strengths: [String]
    var risks: [String]
    var suggestions: [String]
}

// MARK: - SafetyResult

/// 安全性チェックの結果。
struct SafetyResult: Codable, Hashable {
    var isAllowed: Bool
    var blockedTerms: [String]
    var reason: String?
}

// MARK: - AIProvider

/// FABLE パイプラインの各ステージを担う AI プロバイダー抽象。
/// Mock と OpenAI が準拠する。すべて async。
protocol AIProvider: Sendable {

    /// ジャンル分類: ログラインから Save the Cat ジャンルを推定し、ブリーフを生成。
    func classifyGenre(logline: String, format: Format) async throws -> StoryBrief

    /// 13フェーズ構成を生成。
    func generatePhases(brief: StoryBrief, pageCount: Int) async throws -> [PhaseCard]

    /// ページプランを生成（pageCount ページ分）。
    func generatePagePlan(
        brief: StoryBrief,
        phases: [PhaseCard],
        pageCount: Int
    ) async throws -> [PagePlan]

    /// 指定ページのコマ割りを生成。
    func generateLayout(
        page: PagePlan,
        brief: StoryBrief
    ) async throws -> [PanelSpec]

    /// コマにセリフ・効果音を付与して返す。
    func generateDialogue(
        panels: [PanelSpec],
        page: PagePlan,
        brief: StoryBrief
    ) async throws -> [PanelSpec]

    /// 物語全体を批評。
    func critique(bundle: ProjectBundle) async throws -> CritiqueResult

    /// 入力テキストの安全性（著作権侵害等）をチェック。
    func safetyCheck(text: String) async throws -> SafetyResult
}
