import Foundation

// MARK: - ProjectStore

/// プロジェクトの保持・永続化を担うストア。
/// インメモリで保持し、ProjectPersistence（ファイル or SwiftData）に保存する。
/// SwiftData の ModelContext を扱うため MainActor 隔離（View / 各サービスも MainActor）。
@Observable
@MainActor
final class ProjectStore {

    /// 全プロジェクト（束ねたデータ込み）。
    private(set) var bundles: [ProjectBundle]

    /// 現在選択中のプロジェクト ID。
    var selectedProjectID: UUID?

    /// 永続化バックエンド（ファイル or SwiftData）。差し替え可能。
    private let persistence: ProjectPersistence

    // MARK: Init

    /// - Parameters:
    ///   - persistence: 永続化バックエンド。既定はファイル（プレビュー・テスト・フォールバック用）。
    ///                  端末では PlotNameAIApp が SwiftData 版を注入する。
    ///   - seedWithSample: 永続データが空のときサンプルでシードするか。
    init(persistence: ProjectPersistence = FileProjectPersistence(), seedWithSample: Bool = true) {
        self.persistence = persistence

        let loaded = persistence.load()
        if !loaded.isEmpty {
            self.bundles = loaded
        } else if seedWithSample {
            // 初回起動時はサンプル作品でシードする。
            self.bundles = [SampleData.bundle]
                + SampleData.extraProjects.map { ProjectBundle(project: $0) }
        } else {
            self.bundles = []
        }
        self.selectedProjectID = bundles.first?.id
    }

    // MARK: Accessors

    /// 一覧表示用に Project だけ取り出す（更新日の新しい順）。
    var projects: [Project] {
        bundles.map(\.project).sorted { $0.updatedAt > $1.updatedAt }
    }

    /// ユーザーが作成した作品数（同梱サンプルはプラン上限のカウント対象外）。
    var userProjectCount: Int {
        bundles.lazy.filter { !$0.project.isSample }.count
    }

    /// 選択中の束。
    var selectedBundle: ProjectBundle? {
        guard let id = selectedProjectID else { return nil }
        return bundle(for: id)
    }

    func bundle(for id: UUID) -> ProjectBundle? {
        bundles.first { $0.id == id }
    }

    private func index(of id: UUID) -> Int? {
        bundles.firstIndex { $0.id == id }
    }

    // MARK: Mutations

    /// 新規プロジェクトを追加し、その ID を返す。
    @discardableResult
    func addProject(_ project: Project) -> UUID {
        bundles.append(ProjectBundle(project: project))
        selectedProjectID = project.id
        persist()
        return project.id
    }

    /// 束を丸ごと差し替え（生成完了時など）。
    func upsert(_ bundle: ProjectBundle) {
        if let idx = index(of: bundle.id) {
            bundles[idx] = bundle
        } else {
            bundles.append(bundle)
        }
        persist()
    }

    /// プロジェクトのメタ情報を更新。
    func updateProject(_ project: Project) {
        guard let idx = index(of: project.id) else { return }
        var p = project
        p.updatedAt = .now
        bundles[idx].project = p
        persist()
    }

    /// 1コマを更新（キャンバス編集用）。所属する束を走査して見つける。
    func updatePanel(_ panel: PanelSpec) {
        for bIdx in bundles.indices {
            if let pIdx = bundles[bIdx].panels.firstIndex(where: { $0.id == panel.id }) {
                bundles[bIdx].panels[pIdx] = panel
                bundles[bIdx].project.updatedAt = .now
                persist()
                return
            }
        }
    }

    /// 指定束のコマを置き換える（一括）。
    func updatePanel(_ panel: PanelSpec, in projectID: UUID) {
        guard let idx = index(of: projectID),
              let pIdx = bundles[idx].panels.firstIndex(where: { $0.id == panel.id })
        else { return }
        bundles[idx].panels[pIdx] = panel
        bundles[idx].project.updatedAt = .now
        persist()
    }

    /// ページごとの赤入れ（PencilKit）データを保存する。
    /// data が空なら当該ページの注釈を削除する。
    func updateAnnotation(_ data: Data, page: Int, in projectID: UUID) {
        guard let idx = index(of: projectID) else { return }
        if data.isEmpty {
            bundles[idx].annotations.removeValue(forKey: page)
        } else {
            bundles[idx].annotations[page] = data
        }
        bundles[idx].project.updatedAt = .now
        persist()
    }

    /// プロジェクト削除。
    func deleteProject(_ id: UUID) {
        bundles.removeAll { $0.id == id }
        if selectedProjectID == id {
            selectedProjectID = bundles.first?.id
        }
        persist()
    }

    /// 全ローカルデータを削除する（アカウント削除時に使用）。
    /// 同梱サンプルも含めて空にし、空状態を永続化する。
    func deleteAllData() {
        bundles = []
        selectedProjectID = nil
        persist()
    }

    // MARK: Persistence

    /// 即時保存（バックエンドへ委譲）。
    func persist() {
        persistence.save(bundles)
    }
}
