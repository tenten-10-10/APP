import Foundation

// MARK: - Feature

/// プランによってゲートされる機能。
enum Feature: String, Codable, CaseIterable, Identifiable {
    case basicGeneration       // 13フェーズ＋ページプラン生成
    case ipadCanvas            // iPad ネームキャンバス編集
    case imageRoughGeneration  // ラフ画像生成
    case pdfExport             // PDF 書き出し
    case unlimitedProjects     // 無制限プロジェクト
    case prioritySpeed         // 優先生成

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .basicGeneration: return "プロット生成"
        case .ipadCanvas: return "iPadネーム編集"
        case .imageRoughGeneration: return "ラフ画像生成"
        case .pdfExport: return "PDF書き出し"
        case .unlimitedProjects: return "無制限プロジェクト"
        case .prioritySpeed: return "優先生成"
        }
    }
}

// MARK: - SubscriptionEntitlement

/// 現在のプランで利用可能な機能と上限。
struct SubscriptionEntitlement: Codable, Hashable {
    var plan: Plan
    var features: [Feature]
    var limits: Limits

    /// プランごとの数値上限。
    struct Limits: Codable, Hashable {
        var maxProjects: Int        // -1 は無制限
        var monthlyCredits: Int     // 月あたり生成クレジット
        var maxPagesPerProject: Int

        init(maxProjects: Int, monthlyCredits: Int, maxPagesPerProject: Int) {
            self.maxProjects = maxProjects
            self.monthlyCredits = monthlyCredits
            self.maxPagesPerProject = maxPagesPerProject
        }
    }

    init(plan: Plan, features: [Feature], limits: Limits) {
        self.plan = plan
        self.features = features
        self.limits = limits
    }

    func has(_ feature: Feature) -> Bool {
        features.contains(feature)
    }

    /// プランに対応する既定のエンタイトルメントを返す。
    static func defaultEntitlement(for plan: Plan) -> SubscriptionEntitlement {
        switch plan {
        case .free:
            return .init(
                plan: .free,
                features: [.basicGeneration],
                limits: .init(maxProjects: 2, monthlyCredits: 3, maxPagesPerProject: 16)
            )
        case .plus:
            return .init(
                plan: .plus,
                features: [.basicGeneration, .pdfExport],
                limits: .init(maxProjects: 5, monthlyCredits: 30, maxPagesPerProject: 35)
            )
        case .pro:
            return .init(
                plan: .pro,
                features: [.basicGeneration, .pdfExport, .ipadCanvas, .imageRoughGeneration],
                limits: .init(maxProjects: 50, monthlyCredits: 200, maxPagesPerProject: 50)
            )
        case .studio:
            return .init(
                plan: .studio,
                features: Feature.allCases,
                limits: .init(maxProjects: -1, monthlyCredits: 1000, maxPagesPerProject: 120)
            )
        }
    }
}
