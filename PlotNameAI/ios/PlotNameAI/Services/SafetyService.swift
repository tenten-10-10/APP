import Foundation

// MARK: - SafetyEngine

/// 著作権侵害につながる入力を検出する純粋ロジック（同期）。
/// プロバイダーとサービスの両方から再利用する。
struct SafetyEngine: Sendable {

    /// 実在のマンガ・作者名などのデニーリスト（部分一致）。
    /// 注: これは網羅的ではなく、代表例。実運用では拡充する。
    static let deniedTerms: [String] = [
        // 作品名
        "ONE PIECE", "ワンピース", "鬼滅", "鬼滅の刃", "ナルト", "NARUTO",
        "ドラゴンボール", "DRAGON BALL", "進撃の巨人", "呪術廻戦",
        "スラムダンク", "SLAM DUNK", "名探偵コナン", "セーラームーン",
        "ジョジョ", "ハンターハンター", "HUNTER", "チェンソーマン", "推しの子",
        // 作者名
        "尾田栄一郎", "鳥山明", "岸本斉史", "吾峠呼世晴",
        // キャラクター名
        "ルフィ", "ナルト", "悟空", "炭治郎"
    ]

    /// 「○○先生風」「××っぽく」など作風の模倣を促す表現パターン。
    static let styleMimicPatterns: [String] = [
        "先生風", "風に描", "っぽく描", "の絵柄で", "の画風で", "そっくりに"
    ]

    /// テキストを評価して結果を返す。
    func evaluate(text: String) -> SafetyResult {
        let normalized = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
        let upper = text.uppercased()

        var blocked: [String] = []

        for term in Self.deniedTerms {
            let key = term.uppercased()
            if upper.contains(key) || normalized.contains(term.replacingOccurrences(of: " ", with: "")) {
                blocked.append(term)
            }
        }

        let hasStyleMimic = Self.styleMimicPatterns.contains { text.contains($0) }
        if hasStyleMimic {
            blocked.append("作風の模倣表現")
        }

        let isAllowed = blocked.isEmpty
        let reason: String? = isAllowed
            ? nil
            : "実在の作品・作者・作風の模倣に該当する表現が含まれています（\(blocked.joined(separator: "、"))）。オリジナルの設定でお試しください。"

        return SafetyResult(isAllowed: isAllowed, blockedTerms: blocked, reason: reason)
    }
}

// MARK: - SafetyService

/// アプリ層から使う安全性チェックの窓口。
@Observable
final class SafetyService {

    private let engine = SafetyEngine()

    /// 同期チェック（入力欄のリアルタイム検証向け）。
    func check(_ text: String) -> SafetyResult {
        engine.evaluate(text: text)
    }

    /// 許可されているか（簡易）。
    func isAllowed(_ text: String) -> Bool {
        engine.evaluate(text: text).isAllowed
    }
}
