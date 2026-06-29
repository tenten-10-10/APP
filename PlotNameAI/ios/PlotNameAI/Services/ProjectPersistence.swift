import Foundation
#if canImport(SwiftData)
import SwiftData
#endif

// MARK: - ProjectPersistence

/// プロジェクト束（ProjectBundle）の永続化を抽象化するプロトコル。
/// 実装はファイル/Codable（FileProjectPersistence）と
/// SwiftData（SwiftDataProjectPersistence）の2種類。
/// ProjectStore はこのプロトコルにのみ依存し、保存先を差し替え可能にする。
/// ProjectStore（MainActor）から呼ばれ、SwiftData の ModelContext も MainActor で扱うため
/// プロトコル全体を MainActor 隔離にする。
@MainActor
protocol ProjectPersistence {
    /// 全束を読み込む。無ければ空配列。
    func load() -> [ProjectBundle]
    /// 全束を保存（丸ごと置き換え）。
    func save(_ bundles: [ProjectBundle])
}

// MARK: - Shared Codable config

/// 永続化で共有する JSON エンコーダ／デコーダ。
enum ProjectCoding {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - FileProjectPersistence

/// 従来どおり Application Support に JSON ファイルとして保存する実装。
/// プレビュー・テスト・SwiftData 不使用時のフォールバックに使う。
struct FileProjectPersistence: ProjectPersistence {

    let storeURL: URL

    init(fileName: String = "projects.json") {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        self.storeURL = dir.appendingPathComponent(fileName)
    }

    func load() -> [ProjectBundle] {
        guard let data = try? Data(contentsOf: storeURL),
              let bundles = try? ProjectCoding.decoder.decode([ProjectBundle].self, from: data)
        else { return [] }
        return bundles
    }

    func save(_ bundles: [ProjectBundle]) {
        do {
            let data = try ProjectCoding.encoder.encode(bundles)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("FileProjectPersistence save error: \(error)")
            #endif
        }
    }
}

// MARK: - SwiftData model

#if canImport(SwiftData)

/// SwiftData レコード。ProjectBundle を JSON エンコードして payload に格納する。
/// 構造体モデル（ProjectBundle 等）を壊さずに SwiftData の利点（端末内キャッシュ）を得るための薄いラッパ。
@available(iOS 17, *)
@Model
final class ProjectRecord {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date
    var payload: Data

    init(id: UUID, updatedAt: Date, payload: Data) {
        self.id = id
        self.updatedAt = updatedAt
        self.payload = payload
    }
}

// MARK: - SwiftDataProjectPersistence

/// SwiftData をバックエンドにした永続化。各 ProjectBundle を 1 レコードに対応させる。
/// ModelContext は @MainActor 上で扱う（ProjectStore も MainActor 経由で使用）。
@available(iOS 17, *)
@MainActor
struct SwiftDataProjectPersistence: ProjectPersistence {

    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func load() -> [ProjectBundle] {
        let descriptor = FetchDescriptor<ProjectRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.compactMap { record in
            try? ProjectCoding.decoder.decode(ProjectBundle.self, from: record.payload)
        }
    }

    func save(_ bundles: [ProjectBundle]) {
        // 現在の束 ID 集合。
        let currentIDs = Set(bundles.map(\.id))

        // 既存レコードを取得し、辞書化。
        let existing = (try? context.fetch(FetchDescriptor<ProjectRecord>())) ?? []
        var byID: [UUID: ProjectRecord] = [:]
        for record in existing { byID[record.id] = record }

        // 追加・更新。
        for bundle in bundles {
            guard let data = try? ProjectCoding.encoder.encode(bundle) else { continue }
            if let record = byID[bundle.id] {
                record.payload = data
                record.updatedAt = bundle.project.updatedAt
            } else {
                context.insert(
                    ProjectRecord(
                        id: bundle.id,
                        updatedAt: bundle.project.updatedAt,
                        payload: data
                    )
                )
            }
        }

        // 削除（束に存在しないレコードを消す）。
        for record in existing where !currentIDs.contains(record.id) {
            context.delete(record)
        }

        do {
            try context.save()
        } catch {
            #if DEBUG
            print("SwiftDataProjectPersistence save error: \(error)")
            #endif
        }
    }
}

#endif
