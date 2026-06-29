import Foundation

// MARK: - ProjectStatus

/// プロジェクトの進行状態。
enum ProjectStatus: String, Codable, CaseIterable {
    case draft        // 下書き
    case generating   // 生成中
    case ready        // 生成完了
    case archived     // アーカイブ

    var displayName: String {
        switch self {
        case .draft: return "下書き"
        case .generating: return "生成中"
        case .ready: return "完成"
        case .archived: return "アーカイブ"
        }
    }
}

// MARK: - Project

/// 1作品を表すトップレベルのモデル。バックエンドのフィールドに対応。
struct Project: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var format: Format
    var pageCount: Int
    var targetReader: String
    var tone: [String]
    var status: ProjectStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        format: Format = .manga,
        pageCount: Int = 35,
        targetReader: String = "少年・青年",
        tone: [String] = [],
        status: ProjectStatus = .draft,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.format = format
        self.pageCount = pageCount
        self.targetReader = targetReader
        self.tone = tone
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
