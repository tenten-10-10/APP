import Foundation

// MARK: - MockAIProvider

/// 完全オフラインで動作する決定論的プロバイダー。
/// ログラインから一貫した 35 ページ構成を生成する。
/// page1 でフック、phase7 で中間勝利、phase9 で破滅、phase13 で満足、という起伏を作る。
struct MockAIProvider: AIProvider {

    private let safety = SafetyEngine()

    // MARK: classifyGenre

    func classifyGenre(logline: String, format: Format) async throws -> StoryBrief {
        try await Self.simulateDelay()

        // 安全性を先に確認。
        let safetyResult = safety.evaluate(text: logline)
        guard safetyResult.isAllowed else {
            throw AIProviderError.safetyViolation(reason: safetyResult.reason ?? "著作権に抵触する語が含まれています。")
        }

        // ログラインの語からジャンルを決定論的に選ぶ。
        let type = Self.inferType(from: logline)
        let protagonistName = Self.inferProtagonistName(from: logline)

        let brief = StoryBrief(
            projectId: UUID(), // 呼び出し側で projectId を差し替える運用。
            logline: logline.isEmpty ? "ある日常が、ひとつの事件で一変する物語。" : logline,
            theme: Self.inferTheme(for: type),
            saveTheCatType: type,
            subType: type.usageNote,
            protagonist: Protagonist(
                name: protagonistName,
                want: "目の前の問題を解決したい",
                need: "本当の自分と向き合うこと",
                flaw: "他人を信じきれない"
            ),
            antagonist: Antagonist(
                name: "対立する存在",
                goal: "主人公の目的を阻む",
                threat: "主人公が最も恐れるものを突きつける"
            ),
            world: World(
                setting: "主人公の日常と非日常が交差する舞台",
                rules: "選択には必ず代償が伴う"
            )
        )
        return brief
    }

    // MARK: generatePhases

    func generatePhases(brief: StoryBrief, pageCount: Int) async throws -> [PhaseCard] {
        try await Self.simulateDelay()

        let pageBuckets = Self.distributePages(total: pageCount, weights: Self.phaseWeights)

        return Phase.allCases.map { phase in
            let idx = phase.number - 1
            return PhaseCard(
                phaseNumber: phase.number,
                phaseName: phase.phaseName,
                summary: Self.phaseSummary(phase, brief: brief),
                function: Self.phaseFunction(phase),
                emotionalValue: Self.phaseEmotion[idx],
                pages: pageBuckets[idx],
                mustShow: Self.phaseMustShow(phase, brief: brief),
                weaknessAlert: Self.phaseWeakness(phase)
            )
        }
    }

    // MARK: generatePagePlan

    func generatePagePlan(
        brief: StoryBrief,
        phases: [PhaseCard],
        pageCount: Int
    ) async throws -> [PagePlan] {
        try await Self.simulateDelay()

        // ページ番号 -> フェーズ番号の対応表を作る。
        var pageToPhase: [Int: Int] = [:]
        for card in phases {
            for p in card.pages { pageToPhase[p] = card.phaseNumber }
        }

        var plans: [PagePlan] = []
        for page in 1...pageCount {
            let phaseNum = pageToPhase[page] ?? Self.fallbackPhase(forPage: page, of: pageCount)
            let phase = Phase(rawValue: phaseNum) ?? .dailyLife

            let isTurning = Self.isTurningPoint(page: page, phase: phase, pageCount: pageCount)
            let panelCount = Self.panelCount(for: phase, isTurning: isTurning)

            plans.append(
                PagePlan(
                    pageNumber: page,
                    phase: phaseNum,
                    pageGoal: Self.pageGoal(page: page, phase: phase, brief: brief),
                    readerEmotion: Self.readerEmotion(for: phase),
                    turningPoint: isTurning,
                    panelCount: panelCount,
                    lastPanelHook: Self.lastHook(page: page, phase: phase, pageCount: pageCount, brief: brief),
                    dialogueDensity: Self.dialogueDensity(for: phase),
                    visualDensity: Self.visualDensity(for: phase, isTurning: isTurning),
                    whyThisPageExists: Self.whyExists(page: page, phase: phase)
                )
            )
        }
        return plans
    }

    // MARK: generateLayout

    func generateLayout(page: PagePlan, brief: StoryBrief) async throws -> [PanelSpec] {
        try await Self.simulateDelay(short: true)

        let rects = Self.layoutRects(count: page.panelCount)
        let phase = page.phaseEnum ?? .dailyLife

        return rects.enumerated().map { index, rect in
            let panelNumber = index + 1
            let isLast = panelNumber == rects.count
            return PanelSpec(
                pageNumber: page.pageNumber,
                panelNumber: panelNumber,
                layout: rect,
                shot: Self.shot(for: phase, isLast: isLast),
                camera: Self.camera(for: phase, isLast: isLast),
                description: Self.panelDescription(page: page, panel: panelNumber, isLast: isLast, brief: brief),
                characters: [brief.protagonist.name],
                dialogue: "",
                sfx: isLast && page.turningPoint ? "ドクン" : "",
                emotion: page.readerEmotion,
                imagePrompt: Self.imagePrompt(phase: phase, isLast: isLast, brief: brief)
            )
        }
    }

    // MARK: generateDialogue

    func generateDialogue(
        panels: [PanelSpec],
        page: PagePlan,
        brief: StoryBrief
    ) async throws -> [PanelSpec] {
        try await Self.simulateDelay(short: true)

        let lines = Self.dialogueLines(page: page, count: panels.count, brief: brief)
        return panels.enumerated().map { index, panel in
            var updated = panel
            updated.dialogue = lines[index]
            return updated
        }
    }

    // MARK: critique

    func critique(bundle: ProjectBundle) async throws -> CritiqueResult {
        try await Self.simulateDelay()

        let pageCount = bundle.pagePlans.count
        let turningPoints = bundle.pagePlans.filter { $0.turningPoint }.count
        let score = min(95, 70 + turningPoints * 3)

        return CritiqueResult(
            score: score,
            strengths: [
                "1ページ目に強いフックがあります。",
                "フェーズ7で中間の勝利、フェーズ9で破滅の谷が明確です。",
                "感情の起伏が13フェーズに沿って設計されています。"
            ],
            risks: turningPoints < 3
                ? ["ターニングポイントが少なめです。中盤の起伏を増やすと良いでしょう。"]
                : ["終盤の情報量が多くなりがちです。コマ数の調整を検討してください。"],
            suggestions: [
                "破滅（フェーズ9）の前に主人公の油断を1ページ足すと落差が増します。",
                "全\(pageCount)ページのうち、対決（フェーズ11）に最大のコマ数を割り当てましょう。"
            ]
        )
    }

    // MARK: safetyCheck

    func safetyCheck(text: String) async throws -> SafetyResult {
        try await Self.simulateDelay(short: true)
        return safety.evaluate(text: text)
    }

    // MARK: generatePanelRough

    /// コマの内容から決定論的なラフ記述子を生成する（実画像なし）。
    /// シードはコマ ID とコマ番号から固定的に作るため、同じコマからは常に同じラフになる。
    func generatePanelRough(panel: PanelSpec, brief: PanelRoughBrief) async throws -> PanelRough {
        // ラフ生成は他ステージより少し時間がかかる演出。
        try await Self.simulateDelay()

        let seed = Self.roughSeed(for: panel)
        let symbol = Self.roughSymbol(shot: panel.shot, phaseName: brief.phaseName)
        let caption = "\(brief.phaseName)／\(panel.shot)・\(panel.camera)：\(brief.protagonistName)"
        let shapes = Self.roughShapes(seed: seed, shot: panel.shot)

        return PanelRough(
            panelId: panel.id,
            symbolName: symbol,
            caption: caption,
            seed: seed,
            shapes: shapes
        )
    }
}

// MARK: - Mock generation helpers

private extension MockAIProvider {

    /// 疑似的な処理遅延（UIの進捗演出用）。
    static func simulateDelay(short: Bool = false) async throws {
        let nanos: UInt64 = short ? 120_000_000 : 300_000_000
        try await Task.sleep(nanoseconds: nanos)
    }

    // フェーズごとのページ配分の重み（合計に比例配分）。
    static let phaseWeights: [Int] = [3, 2, 2, 3, 2, 3, 2, 3, 2, 1, 4, 2, 2]

    // フェーズごとの感情価（-5...+5）。page1 高揚→破滅で底→満足で回復。
    static let phaseEmotion: [Int] = [1, -1, 2, -2, 1, 3, 4, -2, -5, 0, 2, 3, 5]

    /// total ページを weights に比例配分して、各フェーズのページ番号配列を返す。
    /// 最大剰余法（largest remainder）で決定論的に配分し、合計は常に total に一致する。
    /// total >= フェーズ数 のときは各フェーズに最低1ページを保証する。
    /// total < 13（例: 8P読み切り）のときは低ウェイトのフェーズが0ページになり得る
    /// （13フェーズの骨格が圧縮される）。下流の generatePagePlan は空フェーズを許容する。
    static func distributePages(total: Int, weights: [Int]) -> [[Int]] {
        let n = weights.count
        guard total > 0, n > 0 else { return Array(repeating: [], count: n) }

        let weightSum = max(1, weights.reduce(0, +))
        let raw = weights.map { Double($0) / Double(weightSum) * Double(total) }
        var counts = raw.map { Int($0.rounded(.down)) }   // 床関数。0 になり得る。

        // 端数の大きい順に余りページを配分（決定論的・同点はインデックス昇順）。
        var remaining = total - counts.reduce(0, +)
        let order = raw.enumerated()
            .map { (i: $0.offset, frac: $0.element - $0.element.rounded(.down)) }
            .sorted { $0.frac != $1.frac ? $0.frac > $1.frac : $0.i < $1.i }
        var k = 0
        while remaining > 0 {
            counts[order[k % n].i] += 1
            remaining -= 1
            k += 1
        }

        // ページ数がフェーズ数以上なら全フェーズに最低1ページを保証（最大から借りる）。
        if total >= n {
            for idx in 0..<n where counts[idx] == 0 {
                if let donor = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[donor] > 1 {
                    counts[donor] -= 1
                    counts[idx] = 1
                }
            }
        }

        var buckets: [[Int]] = []
        var page = 1
        for c in counts {
            if c <= 0 {
                buckets.append([])
            } else {
                buckets.append(Array(page..<(page + c)))
                page += c
            }
        }
        return buckets
    }

    /// バケットに載らなかったページの保険的フェーズ割り当て。
    static func fallbackPhase(forPage page: Int, of total: Int) -> Int {
        let ratio = Double(page) / Double(max(1, total))
        return min(13, max(1, Int((ratio * 13).rounded(.up))))
    }

    // MARK: ジャンル推定

    static func inferType(from logline: String) -> SaveTheCatType {
        let text = logline.lowercased()
        let map: [(keys: [String], type: SaveTheCatType)] = [
            (["謎", "事件", "犯人", "なぜ"], .whydunit),
            (["旅", "冒険", "探し", "目指"], .goldenFleece),
            (["力", "能力", "魔法", "覚醒"], .superhero),
            (["相棒", "友", "二人", "出会"], .buddyLove),
            (["怪物", "閉じ", "脱出", "屋敷"], .monsterInTheHouse),
            (["成長", "卒業", "別れ", "喪失"], .ritesOfPassage),
            (["組織", "会社", "ルール", "反逆"], .institutionalized),
            (["願い", "呪い", "変身", "入れ替"], .outOfTheBottle),
            (["逆転", "見下", "底辺", "下剋上"], .foolTriumphant)
        ]
        for entry in map where entry.keys.contains(where: { text.contains($0) }) {
            return entry.type
        }
        return .dudeWithAProblem
    }

    static func inferProtagonistName(from logline: String) -> String {
        logline.isEmpty ? "主人公" : "主人公"
    }

    static func inferTheme(for type: SaveTheCatType) -> String {
        switch type {
        case .monsterInTheHouse: return "罪と向き合う勇気"
        case .goldenFleece: return "旅の果てに自分を知る"
        case .outOfTheBottle: return "得たものより失わないものの価値"
        case .dudeWithAProblem: return "普通の人の中にある強さ"
        case .ritesOfPassage: return "痛みを受け入れて前に進む"
        case .buddyLove: return "他者を信じることの意味"
        case .whydunit: return "真実は自分自身を映す鏡"
        case .foolTriumphant: return "純粋さは最強の武器"
        case .institutionalized: return "個であり続けることの誇り"
        case .superhero: return "力に伴う孤独と責任"
        }
    }

    // MARK: フェーズ本文

    static func phaseSummary(_ phase: Phase, brief: StoryBrief) -> String {
        let hero = brief.protagonist.name
        switch phase {
        case .dailyLife: return "\(hero)の日常と欠点（\(brief.protagonist.flaw)）を提示する。"
        case .incident: return "日常を揺るがす事件が起こる。"
        case .resolve: return "\(hero)が動き出すことを決意する。"
        case .predicament: return "障害が立ちはだかり苦境に陥る。"
        case .help: return "協力者が現れ、突破口が見え始める。"
        case .growth: return "\(hero)が試行錯誤の中で成長する。"
        case .achievement: return "一度目の達成。中間の勝利を掴む。"
        case .ordeal: return "より大きな試練が訪れる。"
        case .ruin: return "すべてを失う破滅の瞬間。"
        case .trigger: return "再起のきっかけ（\(brief.protagonist.need)への気づき）。"
        case .showdown: return "最大の敵との対決。"
        case .elimination: return "障害を排除し、決着をつける。"
        case .satisfaction: return "新しい日常と満足。テーマの回収。"
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

    static func phaseMustShow(_ phase: Phase, brief: StoryBrief) -> [String] {
        switch phase {
        case .dailyLife: return ["主人公の欠点", "守りたい日常"]
        case .incident: return ["事件そのもの", "主人公の動揺"]
        case .resolve: return ["決意の表情", "後戻りできない一歩"]
        case .predicament: return ["立ちはだかる壁", "焦り"]
        case .help: return ["協力者の登場", "信頼の芽生え"]
        case .growth: return ["成長の手応え", "テーマの提示"]
        case .achievement: return ["中間の勝利", "わずかな油断"]
        case .ordeal: return ["強大な敵の本気", "代償"]
        case .ruin: return ["喪失", "どん底の表情"]
        case .trigger: return [brief.protagonist.need, "立ち上がる理由"]
        case .showdown: return ["最終決戦", "覚悟"]
        case .elimination: return ["決着", "敵の排除"]
        case .satisfaction: return ["変化した主人公", "テーマの回収"]
        }
    }

    static func phaseWeakness(_ phase: Phase) -> String? {
        switch phase {
        case .dailyLife: return "説明過多で退屈にならないよう、動きで見せる。"
        case .achievement: return "勝利を喜びすぎて緊張が緩まないよう注意。"
        case .ruin: return "暗くなりすぎて読者が離れないよう、一筋の光を残す。"
        case .showdown: return "ご都合主義の決着にならないよう、伏線を回収する。"
        default: return nil
        }
    }

    // MARK: ページプラン本文

    static func isTurningPoint(page: Int, phase: Phase, pageCount: Int) -> Bool {
        // 各フェーズの最終ページ付近をターニングポイントにする主要フェーズ。
        switch phase {
        case .incident, .achievement, .ruin, .showdown: return true
        default: return page == 1
        }
    }

    static func panelCount(for phase: Phase, isTurning: Bool) -> Int {
        switch phase {
        case .dailyLife: return 6
        case .incident: return 5
        case .ruin: return 3            // 破滅は大ゴマで魅せる
        case .showdown: return 4
        case .satisfaction: return 5
        default: return isTurning ? 4 : 6
        }
    }

    static func pageGoal(page: Int, phase: Phase, brief: StoryBrief) -> String {
        if page == 1 { return "読者を一瞬で引き込む（強いフック）。" }
        switch phase {
        case .achievement: return "中間の勝利を見せ、読者に満足と油断を与える。"
        case .ruin: return "主人公がすべてを失う破滅を印象づける。"
        case .satisfaction: return "テーマを回収し、変化した主人公で締める。"
        default: return "\(phase.phaseName)の役割を1ページで前進させる。"
        }
    }

    static func readerEmotion(for phase: Phase) -> String {
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

    static func lastHook(page: Int, phase: Phase, pageCount: Int, brief: StoryBrief) -> String {
        if page == 1 { return "「これは、ただの始まりに過ぎなかった——」" }
        if page == pageCount { return "（完）静かな最終コマで余韻を残す。" }
        switch phase {
        case .achievement: return "勝ったはずなのに、背後に不穏な影。"
        case .ruin: return "崩れ落ちる主人公。次ページへ引く沈黙。"
        case .showdown: return "次の一撃で決着——というところで次ページへ。"
        default: return "次ページをめくらせる小さな引き。"
        }
    }

    static func dialogueDensity(for phase: Phase) -> Density {
        switch phase {
        case .ruin, .satisfaction: return .low
        case .resolve, .help, .trigger: return .high
        default: return .medium
        }
    }

    static func visualDensity(for phase: Phase, isTurning: Bool) -> Density {
        switch phase {
        case .ruin, .showdown: return .high
        case .dailyLife: return .medium
        default: return isTurning ? .high : .medium
        }
    }

    static func whyExists(page: Int, phase: Phase) -> String {
        if page == 1 { return "つかみ。読者がこの作品を読み続けるかを決めるページ。" }
        return "\(phase.phaseName)フェーズの感情曲線を支えるために必要。"
    }

    // MARK: レイアウト

    /// コマ数に応じたシンプルで読みやすい矩形配置（0...1 比率）。
    /// 座標は中立的な左上原点（LTR）で格納する。マンガの右開き表現は
    /// 描画側（PanelCanvasView / PDFExporter）が X をミラーリングして行う。
    /// すなわち panel1 は LTR では左上だが、ミラー後は右上に表示される。
    static func layoutRects(count: Int) -> [PanelLayout] {
        PanelLayouts.rects(count: count)
    }

    static func shot(for phase: Phase, isLast: Bool) -> String {
        if isLast && (phase == .ruin || phase == .showdown) { return "大ゴマ・ロング" }
        switch phase {
        case .achievement: return "バストアップ"
        case .ruin: return "クローズアップ"
        default: return isLast ? "クローズアップ" : "ミディアム"
        }
    }

    static func camera(for phase: Phase, isLast: Bool) -> String {
        switch phase {
        case .ruin: return "俯瞰"
        case .showdown: return "あおり"
        case .resolve: return "あおり"
        default: return isLast ? "あおり" : "水平"
        }
    }

    static func panelDescription(page: PagePlan, panel: Int, isLast: Bool, brief: StoryBrief) -> String {
        let phase = page.phaseEnum ?? .dailyLife
        if isLast {
            return "ページの引き：\(page.lastPanelHook)"
        }
        return "\(phase.phaseName)：\(brief.protagonist.name)の行動をコマ\(panel)で描写。"
    }

    static func imagePrompt(phase: Phase, isLast: Bool, brief: StoryBrief) -> String {
        "manga panel, \(phase.phaseName), \(brief.theme), monochrome ink, screentone, dynamic composition\(isLast ? ", dramatic" : "")"
    }

    // MARK: セリフ

    static func dialogueLines(page: PagePlan, count: Int, brief: StoryBrief) -> [String] {
        let phase = page.phaseEnum ?? .dailyLife
        let hero = brief.protagonist.name
        let pool: [String]
        switch phase {
        case .dailyLife:
            pool = ["いつも通りの朝だ。", "……何も変わらない毎日。", "\(hero)、また遅刻するよ！", ""]
        case .incident:
            pool = ["なっ……！？", "嘘だろ、こんなことが……", "誰か——！", ""]
        case .resolve:
            pool = ["……決めた。", "オレがやるしかない。", "もう逃げない。", ""]
        case .achievement:
            pool = ["やった……勝ったんだ！", "これで終わりだ。", "……本当に？", ""]
        case .ruin:
            pool = ["そんな……", "……全部、消えた。", "", ""]
        case .trigger:
            pool = ["……まだだ。", "本当に大切なものは……", "立ち上がれ、\(hero)。", ""]
        case .showdown:
            pool = ["ここで……終わらせる！", "覚悟しろ。", "うおおおおっ！", ""]
        case .satisfaction:
            pool = ["……ありがとう。", "また明日。", "", ""]
        default:
            pool = ["行こう。", "大丈夫、きっと。", "……", ""]
        }
        return (0..<count).map { pool[$0 % pool.count] }
    }

    // MARK: ラフ生成（決定論的）

    /// コマ ID とコマ番号から安定したシードを作る。
    static func roughSeed(for panel: PanelSpec) -> Int {
        // UUID のハッシュは実行ごとに変わり得るため、文字列から決定論的に算出する。
        let base = panel.id.uuidString + "#\(panel.pageNumber).\(panel.panelNumber)"
        var hash = 5381
        for byte in base.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(byte)   // djb2（オーバーフロー許容）
        }
        return abs(hash % 100_000)
    }

    /// ショット／フェーズに応じたプレースホルダー SF Symbol。
    static func roughSymbol(shot: String, phaseName: String) -> String {
        if shot.contains("大ゴマ") || shot.contains("ロング") { return "figure.run" }
        if shot.contains("クローズアップ") { return "face.smiling" }
        if shot.contains("バストアップ") { return "person.crop.square" }
        switch phaseName {
        case "破滅": return "cloud.heavyrain"
        case "対決", "排除": return "bolt.fill"
        case "満足": return "sun.max"
        default: return "person.fill"
        }
    }

    /// シードから決定論的に簡単な図形を配置する（0...1 相対座標）。
    static func roughShapes(seed: Int, shot: String) -> [RoughShape] {
        // 背景の地平線（line）＋主要被写体（ellipse）＋補助矩形（rectangle）。
        let cx = 0.30 + Double(seed % 40) / 100.0      // 0.30...0.69
        let size = shot.contains("クローズアップ") ? 0.55 : 0.32
        let groundY = 0.62 + Double(seed % 20) / 100.0 // 0.62...0.81

        return [
            RoughShape(kind: .line, x: 0.06, y: groundY, w: 0.88, h: 0.0),
            RoughShape(kind: .ellipse, x: cx, y: 0.20, w: size, h: size),
            RoughShape(kind: .rectangle, x: 0.10, y: 0.10, w: 0.80, h: 0.80)
        ]
    }
}
