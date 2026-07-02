import Foundation

// MARK: - SampleData

/// ネットワーク無しで全画面が realistic に描画できるよう、完全な作例を提供する。
/// 13フェーズ・35ページ・各ページのコマを含む。
enum SampleData {

    /// 安定した ID（プレビュー間で一貫させるため固定）。
    static let projectID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    // MARK: Project

    static let project = Project(
        id: projectID,
        title: "夜明けのランナー",
        format: .manga,
        pageCount: 35,
        targetReader: "10代〜20代の青年",
        tone: ["熱血", "青春", "再起"],
        status: .ready,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_500_000),
        isSample: true
    )

    // MARK: StoryBrief

    static let brief = StoryBrief(
        projectId: projectID,
        logline: "走ることをやめた元陸上選手の少年が、廃部寸前の部を救うため再び走り出す。",
        theme: "もう一度立ち上がる勇気",
        saveTheCatType: .ritesOfPassage,
        subType: SaveTheCatType.ritesOfPassage.usageNote,
        protagonist: Protagonist(
            name: "ハル",
            want: "もう走らずに静かに過ごしたい",
            need: "過去の挫折と向き合うこと",
            flaw: "失敗を恐れて挑戦を避ける"
        ),
        antagonist: Antagonist(
            name: "過去の自分",
            goal: "ハルを再び立ち止まらせる",
            threat: "挫折の記憶がよみがえる"
        ),
        world: World(
            setting: "地方の県立高校、廃部寸前の陸上部",
            rules: "全国大会出場を逃せば部は廃止される"
        )
    )

    // MARK: Phase cards (13)

    /// 35ページを13フェーズに配分するための重みと感情価（MockAIProviderと整合）。
    private static let phaseWeights: [Int] = [3, 2, 2, 3, 2, 3, 2, 3, 2, 1, 4, 2, 2]
    private static let phaseEmotion: [Int] = [1, -1, 2, -2, 1, 3, 4, -2, -5, 0, 2, 3, 5]

    /// 各フェーズのページ番号配列。
    static let phasePages: [[Int]] = distributePages(total: 35, weights: phaseWeights)

    static let phaseCards: [PhaseCard] = Phase.allCases.map { phase in
        let idx = phase.number - 1
        return PhaseCard(
            phaseNumber: phase.number,
            phaseName: phase.phaseName,
            summary: phaseSummary(phase),
            function: phaseFunction(phase),
            emotionalValue: phaseEmotion[idx],
            pages: phasePages[idx],
            mustShow: phaseMustShow(phase),
            weaknessAlert: phaseWeakness(phase)
        )
    }

    // MARK: Page plans (35)

    static let pagePlans: [PagePlan] = {
        var pageToPhase: [Int: Int] = [:]
        var firstPageOfPhase: [Int: Int] = [:]
        var lastPageOfPhase: [Int: Int] = [:]
        for card in phaseCards {
            for p in card.pages { pageToPhase[p] = card.phaseNumber }
            firstPageOfPhase[card.phaseNumber] = card.pages.first
            lastPageOfPhase[card.phaseNumber] = card.pages.last
        }
        return (1...35).map { page in
            let phaseNum = pageToPhase[page] ?? 1
            let phase = Phase(rawValue: phaseNum) ?? .dailyLife
            let isPhaseFirst = firstPageOfPhase[phaseNum] == page
            let isPhaseLast = lastPageOfPhase[phaseNum] == page
            let isTurning = turningPoint(page: page, phase: phase, isPhaseLast: isPhaseLast)
            return PagePlan(
                pageNumber: page,
                phase: phaseNum,
                pageGoal: pageGoal(page: page, phase: phase,
                                   isPhaseFirst: isPhaseFirst, isPhaseLast: isPhaseLast),
                readerEmotion: readerEmotion(phase),
                turningPoint: isTurning,
                panelCount: panelCount(page: page, phase: phase, isTurning: isTurning),
                lastPanelHook: lastHook(page: page, phase: phase, isPhaseLast: isPhaseLast),
                dialogueDensity: dialogueDensity(phase),
                visualDensity: visualDensity(phase, isTurning: isTurning),
                whyThisPageExists: whyExists(page: page, phase: phase)
            )
        }
    }()

    // MARK: Panels (all pages)

    static let panels: [PanelSpec] = {
        var result: [PanelSpec] = []
        for plan in pagePlans {
            let rects = layoutRects(count: plan.panelCount)
            let phase = plan.phaseEnum ?? .dailyLife
            for (i, rect) in rects.enumerated() {
                let panelNumber = i + 1
                let isLast = panelNumber == rects.count
                result.append(
                    PanelSpec(
                        id: deterministicPanelID(page: plan.pageNumber, panel: panelNumber),
                        pageNumber: plan.pageNumber,
                        panelNumber: panelNumber,
                        layout: rect,
                        shot: isLast ? "クローズアップ" : "ミディアム",
                        camera: phase == .ruin ? "俯瞰" : (isLast ? "あおり" : "水平"),
                        description: isLast
                            ? "引き：\(plan.lastPanelHook)"
                            : "\(phase.phaseName)：ハルの行動をコマ\(panelNumber)で描写。",
                        characters: ["ハル"],
                        dialogue: dialogueLine(phase: phase, panel: panelNumber),
                        sfx: isLast && plan.turningPoint ? "ドクン" : "",
                        emotion: readerEmotion(phase),
                        imagePrompt: "manga panel, \(phase.phaseName), monochrome ink, screentone"
                    )
                )
            }
        }
        return result
    }()

    // MARK: Bundle

    static let bundle = ProjectBundle(
        project: project,
        brief: brief,
        phaseCards: phaseCards,
        pagePlans: pagePlans,
        panels: panels
    )

    /// ホーム一覧用の追加サンプル（中身は空でも一覧表示できる）。
    static let extraProjects: [Project] = [
        Project(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "ガラスの探偵",
            format: .manga,
            pageCount: 35,
            targetReader: "青年",
            tone: ["ミステリー", "シリアス"],
            status: .draft,
            // 完成サンプル（夜明けのランナー）より古い固定日時にして一覧の先頭を譲る。
            createdAt: Date(timeIntervalSince1970: 1_699_500_000),
            updatedAt: Date(timeIntervalSince1970: 1_699_600_000),
            isSample: true
        ),
        Project(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            title: "星屑カフェ",
            format: .webtoon,
            pageCount: 60,
            targetReader: "全年齢",
            tone: ["日常", "ほのぼの"],
            status: .draft,
            createdAt: Date(timeIntervalSince1970: 1_699_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_699_100_000),
            isSample: true
        )
    ]
}

// MARK: - Deterministic generators (mirrors MockAIProvider)

private extension SampleData {

    static func deterministicPanelID(page: Int, panel: Int) -> UUID {
        // 安定した UUID をページ・コマ番号から生成。
        let hex = String(format: "%08x%04x4000a000%012x", page, panel, page * 100 + panel)
        let s = Array(hex)
        func seg(_ r: Range<Int>) -> String { String(s[r]) }
        let str = "\(seg(0..<8))-\(seg(8..<12))-\(seg(12..<16))-\(seg(16..<20))-\(seg(20..<32))"
        return UUID(uuidString: str) ?? UUID()
    }

    static func distributePages(total: Int, weights: [Int]) -> [[Int]] {
        let weightSum = weights.reduce(0, +)
        var counts = weights.map { max(1, Int((Double($0) / Double(weightSum) * Double(total)).rounded())) }
        var diff = total - counts.reduce(0, +)
        var i = 0
        while diff != 0 {
            let idx = i % counts.count
            if diff > 0 { counts[idx] += 1; diff -= 1 }
            else if counts[idx] > 1 { counts[idx] -= 1; diff += 1 }
            i += 1
        }
        var buckets: [[Int]] = []
        var page = 1
        for c in counts {
            buckets.append(Array(page..<(page + c)))
            page += c
        }
        return buckets
    }

    static func phaseSummary(_ phase: Phase) -> String {
        switch phase {
        case .dailyLife: return "走ることをやめたハルの静かな日常と、その奥にある後悔を描く。"
        case .incident: return "廃部の知らせ。後輩の必死な姿が日常を揺らす。"
        case .resolve: return "ハルが「最後にもう一度だけ」と再起を決意する。"
        case .predicament: return "ブランクと故障の不安、周囲の冷たい目が立ちはだかる。"
        case .help: return "かつてのライバルが手を差し伸べ、練習が動き出す。"
        case .growth: return "地道な練習でタイムが戻り始め、チームに熱が宿る。"
        case .achievement: return "予選を突破。中間の勝利に部が沸く。"
        case .ordeal: return "強豪校との壁、そしてハルの古傷が再発する。"
        case .ruin: return "本番で転倒。ハルは再び走る意味を見失う。"
        case .trigger: return "後輩の言葉でハルは『なぜ走るのか』に気づく。"
        case .showdown: return "決勝レース。過去の自分との最終決戦。"
        case .elimination: return "恐怖を振り切り、ハルがゴールテープを切る。"
        case .satisfaction: return "新しい朝。ハルは仲間と再び走り出す。"
        }
    }

    static func phaseFunction(_ phase: Phase) -> String {
        switch phase {
        case .dailyLife: return "セットアップ／共感づくり"
        case .incident: return "インサイティング・インシデント"
        case .resolve: return "第一幕の転換"
        case .predicament: return "葛藤の導入"
        case .help: return "味方・サブプロット"
        case .growth: return "お楽しみ（プロミス）"
        case .achievement: return "ミッドポイント（偽の勝利）"
        case .ordeal: return "迫りくる悪い奴ら"
        case .ruin: return "オール・イズ・ロスト"
        case .trigger: return "魂の暗い夜→閃き"
        case .showdown: return "第三幕・クライマックス"
        case .elimination: return "フィナーレ"
        case .satisfaction: return "ファイナルイメージ"
        }
    }

    static func phaseMustShow(_ phase: Phase) -> [String] {
        switch phase {
        case .dailyLife: return ["ハルの欠点", "走らない理由"]
        case .incident: return ["廃部通告", "後輩の涙"]
        case .resolve: return ["決意の表情", "走り出す一歩"]
        case .predicament: return ["ブランクの壁", "周囲の不信"]
        case .help: return ["ライバルの登場", "信頼の芽生え"]
        case .growth: return ["タイム回復", "テーマの提示"]
        case .achievement: return ["予選突破", "わずかな油断"]
        case .ordeal: return ["強豪の実力", "古傷の再発"]
        case .ruin: return ["転倒", "どん底の表情"]
        case .trigger: return ["走る本当の理由", "立ち上がる動機"]
        case .showdown: return ["決勝レース", "覚悟"]
        case .elimination: return ["ゴール", "恐怖の克服"]
        case .satisfaction: return ["変化したハル", "テーマの回収"]
        }
    }

    static func phaseWeakness(_ phase: Phase) -> String? {
        switch phase {
        case .dailyLife: return "説明過多で退屈にならないよう、動きで見せる。"
        case .achievement: return "勝利を喜びすぎて緊張が緩まないよう注意。"
        case .ruin: return "暗くなりすぎないよう、一筋の光を残す。"
        case .showdown: return "ご都合主義にならないよう伏線を回収する。"
        default: return nil
        }
    }

    static func turningPoint(page: Int, phase: Phase, isPhaseLast: Bool) -> Bool {
        // 転換点は主要フェーズの「最終ページ」だけ（MockAIProviderと同一の規則）。
        switch phase {
        case .incident, .achievement, .ruin, .showdown: return isPhaseLast
        default: return page == 1
        }
    }

    static func panelCount(page: Int, phase: Phase, isTurning: Bool) -> Int {
        if page == 1 { return 1 }   // 1ページ目は大ゴマ1枚のフック
        switch phase {
        case .dailyLife: return 6
        case .incident: return 5
        case .ruin: return 3
        case .showdown: return 4
        case .satisfaction: return 5
        default: return isTurning ? 4 : 6
        }
    }

    static func pageGoal(page: Int, phase: Phase, isPhaseFirst: Bool, isPhaseLast: Bool) -> String {
        if page == 1 { return "読者を一瞬で引き込む（強いフック）。" }
        if isPhaseLast {
            switch phase {
            case .achievement: return "中間の勝利を見せ、満足と油断を与える。"
            case .ruin: return "ハルがすべてを失う破滅を印象づける。"
            case .satisfaction: return "テーマを回収し、変化したハルで締める。"
            default: return "\(phase.phaseName)を締め、次の展開への期待を作る。"
            }
        }
        if isPhaseFirst { return "\(phase.phaseName)へ場面を切り替え、空気の変化を見せる。" }
        return "\(phase.phaseName)を深め、ハルの感情を一段階動かす。"
    }

    static func readerEmotion(_ phase: Phase) -> String {
        switch phase {
        case .dailyLife: return "共感・好奇心"
        case .incident: return "驚き"
        case .resolve: return "高揚"
        case .predicament: return "不安"
        case .help: return "安堵"
        case .growth: return "わくわく"
        case .achievement: return "達成感"
        case .ordeal: return "緊張"
        case .ruin: return "絶望"
        case .trigger: return "再起への期待"
        case .showdown: return "手に汗"
        case .elimination: return "カタルシス"
        case .satisfaction: return "余韻・満足"
        }
    }

    static func lastHook(page: Int, phase: Phase, isPhaseLast: Bool) -> String {
        if page == 1 { return "「もう、二度と走らないと決めたんだ——」" }
        if page == 35 { return "（完）朝日の中、ハルが駆け出す最終コマ。" }
        switch phase {
        case .achievement: return "勝ったはずなのに、膝に走る鈍い痛み。"
        case .ruin: return "崩れ落ちるハル。観客の声が遠ざかる。"
        case .showdown: return "残り10メートル——というところで次ページへ。"
        default:
            return isPhaseLast
                ? "\(phase.phaseName)の結末を見せ切らずに次ページへ引く。"
                : "小さな違和感やセリフの余韻で次ページへつなぐ。"
        }
    }

    static func dialogueDensity(_ phase: Phase) -> Density {
        switch phase {
        case .ruin, .satisfaction: return .low
        case .resolve, .help, .trigger: return .high
        default: return .medium
        }
    }

    static func visualDensity(_ phase: Phase, isTurning: Bool) -> Density {
        switch phase {
        case .ruin, .showdown: return .high
        case .dailyLife: return .medium
        default: return isTurning ? .high : .medium
        }
    }

    static func whyExists(page: Int, phase: Phase) -> String {
        if page == 1 { return "つかみ。読者が読み続けるかを決めるページ。" }
        return "\(phase.phaseName)フェーズの感情曲線を支えるために必要。"
    }

    static func dialogueLine(phase: Phase, panel: Int) -> String {
        // コマ数(最大6)ぶん重複しないよう各フェーズ6本。""は意図的な無言コマ（間）。
        let pool: [String]
        switch phase {
        case .dailyLife: pool = ["……いつも通りの朝だ。", "ハル、また部活サボり？", "もう走らないって決めたんだ。",
                                 "……別に、いいだろ。", "（グラウンドの歓声が遠くに聞こえる）", ""]
        case .incident: pool = ["陸上部、廃部だって……！", "部員が足りないんです……", "先輩、お願いします！",
                                "……オレには関係ない。", "（言葉とは裏腹に、足が止まる）", ""]
        case .resolve: pool = ["……最後に、もう一度だけ。", "本気なの？", "オレが走る。",
                               "もう逃げない。", "見ててくれ。", ""]
        case .achievement: pool = ["予選突破だ！", "やったぞ……！", "ハル、お前すげえよ！",
                                   "……この痛み、なんだ？", "……気のせいだ。", ""]
        case .ruin: pool = ["うっ……！", "ハル！！", "……また、ダメだった。",
                            "", "（雨の音だけが残る）", ""]
        case .trigger: pool = ["先輩の背中を見て走り始めたんです。", "……オレの、背中？", "走る理由は、速さだけじゃない。",
                               "立て、ハル。", "……ああ。", ""]
        case .showdown: pool = ["ここで……終わらせる！", "過去の自分に勝つ。", "ハル、いけーっ！",
                                "（心臓の音）", "うおおおっ！", ""]
        case .satisfaction: pool = ["……ありがとう、みんな。", "また明日、走ろう。", "うん、また明日。",
                                    "（新しい朝の光）", "", ""]
        default: pool = ["行こう。", "大丈夫、きっと。", "……", "ああ。", "先は長いぞ。", ""]
        }
        return pool[(panel - 1) % pool.count]
    }

    /// 共有テンプレートを使用（MockAIProvider と同一）。
    static func layoutRects(count: Int) -> [PanelLayout] {
        PanelLayouts.rects(count: count)
    }
}
