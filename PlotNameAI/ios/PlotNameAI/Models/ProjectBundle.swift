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

    init(
        project: Project,
        brief: StoryBrief? = nil,
        phaseCards: [PhaseCard] = [],
        pagePlans: [PagePlan] = [],
        panels: [PanelSpec] = []
    ) {
        self.project = project
        self.brief = brief
        self.phaseCards = phaseCards
        self.pagePlans = pagePlans
        self.panels = panels
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
