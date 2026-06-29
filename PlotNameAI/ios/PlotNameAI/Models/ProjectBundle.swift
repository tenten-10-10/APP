import Foundation

// MARK: - ProjectBundle

/// 1プロジェクトに紐づく全データを束ねる集約。永続化・画面間共有の単位。
struct ProjectBundle: Codable, Identifiable, Hashable {
    var id: UUID { project.id }

    var project: Project
    var brief: StoryBrief?
    var phaseCards: [PhaseCard]
    var pagePlans: [PagePlan]
    var panels: [PanelSpec]
    /// ページ番号 → PencilKit 赤入れ（PKDrawing をシリアライズした Data）。
    /// iPad の Apple Pencil 注釈をページ単位で保存する。旧データには存在しないため欠落時は空。
    var annotations: [Int: Data]

    init(
        project: Project,
        brief: StoryBrief? = nil,
        phaseCards: [PhaseCard] = [],
        pagePlans: [PagePlan] = [],
        panels: [PanelSpec] = [],
        annotations: [Int: Data] = [:]
    ) {
        self.project = project
        self.brief = brief
        self.phaseCards = phaseCards
        self.pagePlans = pagePlans
        self.panels = panels
        self.annotations = annotations
    }

    // 旧データ（annotations キーなし）も読めるよう、欠落時は空辞書にフォールバックする。
    private enum CodingKeys: String, CodingKey {
        case project, brief, phaseCards, pagePlans, panels, annotations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        project = try c.decode(Project.self, forKey: .project)
        brief = try c.decodeIfPresent(StoryBrief.self, forKey: .brief)
        phaseCards = try c.decodeIfPresent([PhaseCard].self, forKey: .phaseCards) ?? []
        pagePlans = try c.decodeIfPresent([PagePlan].self, forKey: .pagePlans) ?? []
        panels = try c.decodeIfPresent([PanelSpec].self, forKey: .panels) ?? []
        annotations = try c.decodeIfPresent([Int: Data].self, forKey: .annotations) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(project, forKey: .project)
        try c.encodeIfPresent(brief, forKey: .brief)
        try c.encode(phaseCards, forKey: .phaseCards)
        try c.encode(pagePlans, forKey: .pagePlans)
        try c.encode(panels, forKey: .panels)
        try c.encode(annotations, forKey: .annotations)
    }

    /// 指定ページのコマをコマ番号順に返す。
    func panels(onPage page: Int) -> [PanelSpec] {
        panels
            .filter { $0.pageNumber == page }
            .sorted { $0.panelNumber < $1.panelNumber }
    }

    /// 指定ページのプランを返す。
    func pagePlan(_ page: Int) -> PagePlan? {
        pagePlans.first { $0.pageNumber == page }
    }
}
