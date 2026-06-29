import Foundation

// MARK: - ProjectStore

/// プロジェクトの保持・永続化を担うストア。
/// インメモリで保持し、Codable で Application Support に保存する。
@Observable
final class ProjectStore {

    /// 全プロジェクト（束ねたデータ込み）。
    private(set) var bundles: [ProjectBundle]

    /// 現在選択中のプロジェクト ID。
    var selectedProjectID: UUID?

    /// 永続化先 URL。
    private let storeURL: URL

    // MARK: Init

    init(seedWithSample: Bool = true, fileName: String = "projects.json") {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        self.storeURL = dir.appendingPathComponent(fileName)

        if let loaded = Self.load(from: storeURL), !loaded.isEmpty {
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

    /// プロジェクト削除。
    func deleteProject(_ id: UUID) {
        bundles.removeAll { $0.id == id }
        if selectedProjectID == id {
            selectedProjectID = bundles.first?.id
        }
        persist()
    }

    // MARK: Persistence

    /// 即時保存。
    func persist() {
        do {
            let data = try Self.encoder.encode(bundles)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            // 永続化失敗はアプリ動作を止めない（ログのみ）。
            #if DEBUG
            print("ProjectStore persist error: \(error)")
            #endif
        }
    }

    private static func load(from url: URL) -> [ProjectBundle]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode([ProjectBundle].self, from: data)
    }

    // MARK: Codable config

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
