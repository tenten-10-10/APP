import Foundation

// MARK: - Format

/// 作品フォーマット。バックエンドと同一の rawValue を維持する。
enum Format: String, Codable, CaseIterable, Identifiable {
    case manga
    case webtoon
    case film
    case novel
    case trpg

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manga: return "マンガ"
        case .webtoon: return "ウェブトゥーン"
        case .film: return "映画"
        case .novel: return "小説"
        case .trpg: return "TRPG"
        }
    }
}

// MARK: - Save the Cat genre

/// Save the Cat! の 10 ジャンル。displayName と用途メモを持つ。
enum SaveTheCatType: String, Codable, CaseIterable, Identifiable {
    case monsterInTheHouse
    case goldenFleece
    case outOfTheBottle
    case dudeWithAProblem
    case ritesOfPassage
    case buddyLove
    case whydunit
    case foolTriumphant
    case institutionalized
    case superhero

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monsterInTheHouse: return "モンスターハウス"
        case .goldenFleece: return "金の羊毛"
        case .outOfTheBottle: return "魔法のランプ"
        case .dudeWithAProblem: return "難題に直面した男"
        case .ritesOfPassage: return "通過儀礼"
        case .buddyLove: return "バディとの友情"
        case .whydunit: return "なぜやったか（謎解き）"
        case .foolTriumphant: return "愚か者の勝利"
        case .institutionalized: return "組織の中で"
        case .superhero: return "スーパーヒーロー"
        }
    }

    /// いつ使うかの短い指針。
    var usageNote: String {
        switch self {
        case .monsterInTheHouse:
            return "閉じた空間と脅威。罪が招いた怪物から逃げ、立ち向かう。"
        case .goldenFleece:
            return "旅と成長。目的地を目指す道中で主人公が変わる。"
        case .outOfTheBottle:
            return "願いが叶う／呪い。特別な力を得て学びを得る。"
        case .dudeWithAProblem:
            return "巻き込まれ型。普通の人物が非常事態に立ち向かう。"
        case .ritesOfPassage:
            return "人生の痛みと受容。喪失や変化を乗り越える。"
        case .buddyLove:
            return "二人の関係性。出会いと衝突を経て絆が深まる。"
        case .whydunit:
            return "謎の追究。真相を追ううちに自分の闇に気づく。"
        case .foolTriumphant:
            return "見くびられた者の逆転。純粋さが体制を打ち破る。"
        case .institutionalized:
            return "組織と個人。集団に属するか抗うかの葛藤。"
        case .superhero:
            return "並外れた者の宿命。力ゆえの孤独と責任。"
        }
    }
}

// MARK: - Phase (13-phase structure)

/// 13フェーズ構造の定義。1...13 の固定番号と日本語名を持つ。
enum Phase: Int, Codable, CaseIterable, Identifiable {
    case dailyLife = 1      // 日常
    case incident = 2       // 事件
    case resolve = 3        // 決意
    case predicament = 4    // 苦境
    case help = 5           // 助け
    case growth = 6         // 成長
    case achievement = 7    // 達成
    case ordeal = 8         // 試練
    case ruin = 9           // 破滅
    case trigger = 10       // 契機
    case showdown = 11      // 対決
    case elimination = 12   // 排除
    case satisfaction = 13  // 満足

    var id: Int { rawValue }

    /// 1...13 のフェーズ番号。
    var number: Int { rawValue }

    var phaseName: String {
        switch self {
        case .dailyLife: return "日常"
        case .incident: return "事件"
        case .resolve: return "決意"
        case .predicament: return "苦境"
        case .help: return "助け"
        case .growth: return "成長"
        case .achievement: return "達成"
        case .ordeal: return "試練"
        case .ruin: return "破滅"
        case .trigger: return "契機"
        case .showdown: return "対決"
        case .elimination: return "排除"
        case .satisfaction: return "満足"
        }
    }

    /// 番号からフェーズを得る。範囲外は nil。
    static func from(number: Int) -> Phase? {
        Phase(rawValue: number)
    }
}

// MARK: - Density

/// 密度（セリフ量・画面情報量など）。
enum Density: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }
}

// MARK: - Plan

/// 課金プラン。
enum Plan: String, Codable, CaseIterable, Identifiable {
    case free
    case plus
    case pro
    case studio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .plus: return "Plus"
        case .pro: return "Pro"
        case .studio: return "Studio"
        }
    }

    /// 月額（円）。Free は 0。
    var monthlyPriceYen: Int {
        switch self {
        case .free: return 0
        case .plus: return 980
        case .pro: return 2980
        case .studio: return 6800
        }
    }

    /// 表示用の価格文字列。
    var priceLabel: String {
        switch self {
        case .free: return "無料"
        default: return "¥\(monthlyPriceYen.formatted())/月"
        }
    }
}
