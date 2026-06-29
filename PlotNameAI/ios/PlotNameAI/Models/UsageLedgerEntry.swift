import Foundation

// MARK: - UsageLedgerEntry

/// クレジット消費・付与の台帳エントリ。
struct UsageLedgerEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var projectId: UUID?
    var stage: GenerationStage?
    var creditsDelta: Int      // 消費は負、付与は正
    var note: String
    var timestamp: Date

    init(
        id: UUID = UUID(),
        projectId: UUID? = nil,
        stage: GenerationStage? = nil,
        creditsDelta: Int,
        note: String = "",
        timestamp: Date = .now
    ) {
        self.id = id
        self.projectId = projectId
        self.stage = stage
        self.creditsDelta = creditsDelta
        self.note = note
        self.timestamp = timestamp
    }
}
