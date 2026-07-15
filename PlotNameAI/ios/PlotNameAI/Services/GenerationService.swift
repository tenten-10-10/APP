import Foundation

// MARK: - GenerationService

/// FABLE パイプラインを AIProvider 経由で実行し、ステージ／ページ単位の進捗を publish する。
/// 結果は ProjectStore に保存する。
@Observable
@MainActor
final class GenerationService {

    /// 進行中のジョブ（nil なら待機中）。
    private(set) var currentJob: GenerationJob?

    /// 直近の批評結果。
    private(set) var lastCritique: CritiqueResult?

    /// エラー（UI 表示用）。
    var errorMessage: String?

    /// 生成中かどうか。
    var isRunning: Bool { currentJob != nil && !(currentJob?.isFinished ?? true) }

    private let store: ProjectStore
    private let usage: UsageService
    private let config: AppConfig

    init(store: ProjectStore, usage: UsageService, config: AppConfig) {
        self.store = store
        self.usage = usage
        self.config = config
    }

    // MARK: Pipeline

    /// ログラインから 1 作品を丸ごと生成する。
    /// 各ステージで進捗を更新し、完了後に ProjectStore へ保存する。
    func generate(projectID: UUID, logline: String, pageCount: Int = 35) async {
        let provider = config.makeProvider()
        errorMessage = nil
        lastCritique = nil

        var job = GenerationJob(projectId: projectID, message: "生成を開始します…")
        currentJob = job

        do {
            // 0) 安全性チェック（最初に弾く）。
            update(&job, stage: .safetyCheck, progress: 0.02, message: "安全性を確認中…")
            let safety = try await provider.safetyCheck(text: logline)
            guard safety.isAllowed else {
                throw AIProviderError.safetyViolation(reason: safety.reason ?? "不許可の語が含まれています。")
            }
            usage.spend(0, projectId: projectID, stage: .safetyCheck, note: "安全性チェック")

            // 1) ジャンル分類 → ブリーフ。
            update(&job, stage: .classifyGenre, progress: 0.1, message: "ジャンルを分類中…")
            var brief = try await provider.classifyGenre(logline: logline, format: .manga)
            brief.projectId = projectID  // projectId を確定。
            // テキスト生成ステージはクレジット非消費（クレジットはラフ画像生成用）。
            // 台帳には記録だけ残す（消費0）。
            usage.spend(0, projectId: projectID, stage: .classifyGenre, note: "ジャンル分類")

            // 2) 13フェーズ。
            update(&job, stage: .generatePhases, progress: 0.25, message: "13フェーズを構成中…")
            let phases = try await provider.generatePhases(brief: brief, pageCount: pageCount)
            usage.spend(0, projectId: projectID, stage: .generatePhases, note: "13フェーズ生成")

            // 3) ページプラン。
            update(&job, stage: .generatePagePlan, progress: 0.4, message: "\(pageCount)ページのプランを設計中…")
            let pagePlans = try await provider.generatePagePlan(brief: brief, phases: phases, pageCount: pageCount)
            usage.spend(0, projectId: projectID, stage: .generatePagePlan, note: "ページプラン生成")

            // 4) & 5) ページごとにコマ割り＋セリフ。
            var allPanels: [PanelSpec] = []
            for (i, plan) in pagePlans.enumerated() {
                let pageProgress = 0.5 + 0.4 * (Double(i) / Double(max(1, pagePlans.count)))
                update(&job, stage: .generateLayout, progress: pageProgress,
                       message: "コマ割り中… (\(i + 1)/\(pagePlans.count)ページ)")
                let layout = try await provider.generateLayout(page: plan, brief: brief)

                update(&job, stage: .generateDialogue, progress: pageProgress,
                       message: "セリフ生成中… (\(i + 1)/\(pagePlans.count)ページ)")
                let withDialogue = try await provider.generateDialogue(panels: layout, page: plan, brief: brief)
                allPanels.append(contentsOf: withDialogue)
            }
            usage.spend(0, projectId: projectID, stage: .generateLayout, note: "コマ割り＋セリフ")

            // 6) 批評。
            update(&job, stage: .critique, progress: 0.95, message: "全体を批評中…")
            var bundle = store.bundle(for: projectID) ?? ProjectBundle(project: Project(title: brief.logline))
            bundle.brief = brief
            bundle.phaseCards = phases
            bundle.pagePlans = pagePlans
            bundle.panels = allPanels
            let critique = try await provider.critique(bundle: bundle)
            lastCritique = critique

            // プロジェクトのステータスを ready に。
            bundle.project.status = .ready
            bundle.project.pageCount = pageCount
            bundle.project.updatedAt = .now
            if bundle.project.title.isEmpty {
                bundle.project.title = "無題のネーム"
            }
            store.upsert(bundle)

            // 完了。
            job.progress = 1.0
            job.isFinished = true
            job.finishedAt = .now
            job.message = "生成が完了しました（スコア \(critique.score)）。"
            currentJob = job

        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // 失敗時はジョブを終了状態にして残す。
            job.isFinished = true
            job.finishedAt = .now
            job.message = "生成に失敗しました。"
            currentJob = job
            // 失敗したプロジェクトは draft に戻す。
            if var bundle = store.bundle(for: projectID) {
                bundle.project.status = .draft
                store.upsert(bundle)
            }
        }
    }

    /// 進行中ジョブをクリアする。
    func reset() {
        currentJob = nil
        errorMessage = nil
    }

    // MARK: Helpers

    private func update(_ job: inout GenerationJob, stage: GenerationStage, progress: Double, message: String) {
        job.stage = stage
        job.progress = progress
        job.message = message
        currentJob = job
    }
}
