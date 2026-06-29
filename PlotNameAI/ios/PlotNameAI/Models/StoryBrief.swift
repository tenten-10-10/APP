import Foundation

// MARK: - Character

/// 登場人物（主人公）の欲求・必要・欠点を保持する。
struct Protagonist: Codable, Hashable {
    var name: String
    var want: String   // 表向きの欲求
    var need: String   // 本当に必要なもの
    var flaw: String   // 欠点

    init(name: String, want: String, need: String, flaw: String) {
        self.name = name
        self.want = want
        self.need = need
        self.flaw = flaw
    }
}

/// 敵対者。
struct Antagonist: Codable, Hashable {
    var name: String
    var goal: String
    var threat: String

    init(name: String, goal: String, threat: String) {
        self.name = name
        self.goal = goal
        self.threat = threat
    }
}

/// 世界観。
struct World: Codable, Hashable {
    var setting: String
    var rules: String

    init(setting: String, rules: String) {
        self.setting = setting
        self.rules = rules
    }
}

// MARK: - StoryBrief

/// 物語の骨子。ジャンル分類・テーマ・登場人物を束ねる。
struct StoryBrief: Codable, Identifiable, Hashable {
    /// projectId をそのまま識別子に使う（1プロジェクト1ブリーフ）。
    var id: UUID { projectId }

    var projectId: UUID
    var logline: String
    var theme: String
    var saveTheCatType: SaveTheCatType
    var subType: String
    var protagonist: Protagonist
    var antagonist: Antagonist?
    var world: World?

    init(
        projectId: UUID,
        logline: String,
        theme: String,
        saveTheCatType: SaveTheCatType,
        subType: String = "",
        protagonist: Protagonist,
        antagonist: Antagonist? = nil,
        world: World? = nil
    ) {
        self.projectId = projectId
        self.logline = logline
        self.theme = theme
        self.saveTheCatType = saveTheCatType
        self.subType = subType
        self.protagonist = protagonist
        self.antagonist = antagonist
        self.world = world
    }
}
