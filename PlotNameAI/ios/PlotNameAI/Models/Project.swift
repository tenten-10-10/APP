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
    /// 同梱のショーケース作品か。true のものはプラン上限のカウント対象外。
    var isSample: Bool

    init(
        id: UUID = UUID(),
        title: String,
        format: Format = .manga,
        pageCount: Int = 35,
        targetReader: String = "少年・青年",
        tone: [String] = [],
        status: ProjectStatus = .draft,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isSample: Bool = false
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
        self.isSample = isSample
    }

    // 旧データ（isSample キーなし）も読めるよう、欠落時は false にフォールバックする。
    private enum CodingKeys: String, CodingKey {
        case id, title, format, pageCount, targetReader, tone, status, createdAt, updatedAt, isSample
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        format = try c.decode(Format.self, forKey: .format)
        pageCount = try c.decode(Int.self, forKey: .pageCount)
        targetReader = try c.decode(String.self, forKey: .targetReader)
        tone = try c.decode([String].self, forKey: .tone)
        status = try c.decode(ProjectStatus.self, forKey: .status)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        isSample = try c.decodeIfPresent(Bool.self, forKey: .isSample) ?? false
    }
}
