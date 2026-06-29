import Foundation

// MARK: - OpenAIProvider

/// OpenAI 等のリモート LLM を使う本番プロバイダーのスタブ。
/// APIキーは AppConfig から読み取る想定。本環境では未実装で notConfigured を投げる。
///
/// 実装メモ（将来）:
/// - 各メソッドで responseFormat=json_schema を用い、本アプリの Codable 型に直接デコードする。
/// - safetyCheck は moderation エンドポイント＋ローカル著作権デニーリストの併用。
/// - レート制限・リトライは GenerationService 側でハンドリングしない設計とする。
struct OpenAIProvider: AIProvider {

    let apiKey: String?
    let model: String

    init(apiKey: String?, model: String = "gpt-4o-mini") {
        self.apiKey = apiKey
        self.model = model
    }

    /// キーが無ければ未設定エラー。
    private func requireKey() throws -> String {
        guard let key = apiKey, !key.isEmpty else {
            throw AIProviderError.notConfigured
        }
        return key
    }

    func classifyGenre(logline: String, format: Format) async throws -> StoryBrief {
        _ = try requireKey()
        throw AIProviderError.notConfigured
    }

    func generatePhases(brief: StoryBrief, pageCount: Int) async throws -> [PhaseCard] {
        _ = try requireKey()
        throw AIProviderError.notConfigured
    }

    func generatePagePlan(brief: StoryBrief, phases: [PhaseCard], pageCount: Int) async throws -> [PagePlan] {
        _ = try requireKey()
        throw AIProviderError.notConfigured
    }

    func generateLayout(page: PagePlan, brief: StoryBrief) async throws -> [PanelSpec] {
        _ = try requireKey()
        throw AIProviderError.notConfigured
    }

    func generateDialogue(panels: [PanelSpec], page: PagePlan, brief: StoryBrief) async throws -> [PanelSpec] {
        _ = try requireKey()
        throw AIProviderError.notConfigured
    }

    func critique(bundle: ProjectBundle) async throws -> CritiqueResult {
        _ = try requireKey()
        throw AIProviderError.notConfigured
    }

    func safetyCheck(text: String) async throws -> SafetyResult {
        _ = try requireKey()
        throw AIProviderError.notConfigured
    }

    func generatePanelRough(panel: PanelSpec, brief: PanelRoughBrief) async throws -> PanelRough {
        // 実装メモ（将来）: images/generations 等でラフを生成し、
        // 生成結果をローカルにキャッシュして PanelRough へ橋渡しする。
        _ = try requireKey()
        throw AIProviderError.notConfigured
    }
}
