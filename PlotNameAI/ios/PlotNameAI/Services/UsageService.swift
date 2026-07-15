import Foundation

// MARK: - UsageService

/// クレジット台帳と残量管理。月あたりの上限はエンタイトルメントから取得。
@Observable
final class UsageService {

    /// 台帳エントリ（新しい順に追加していく）。
    private(set) var ledger: [UsageLedgerEntry] = []

    /// 当月に付与されたクレジット総量。
    private(set) var monthlyAllowance: Int

    init(monthlyAllowance: Int = 3) {
        self.monthlyAllowance = monthlyAllowance
    }

    // MARK: Derived

    /// これまでに消費したクレジット（正の値）。
    var consumedCredits: Int {
        ledger.filter { $0.creditsDelta < 0 }.reduce(0) { $0 - $1.creditsDelta }
    }

    /// 残りクレジット。
    var remainingCredits: Int {
        max(0, monthlyAllowance - consumedCredits)
    }

    /// 指定クレジットを消費可能か。
    func canSpend(_ amount: Int) -> Bool {
        remainingCredits >= amount
    }

    // MARK: Mutations

    /// 月あたりの付与量を更新（プラン変更時など）。
    func updateAllowance(_ allowance: Int) {
        monthlyAllowance = allowance
    }

    /// クレジットを消費する。足りなければ false。
    @discardableResult
    func spend(_ amount: Int, projectId: UUID?, stage: GenerationStage?, note: String) -> Bool {
        guard canSpend(amount) else { return false }
        ledger.insert(
            UsageLedgerEntry(
                projectId: projectId,
                stage: stage,
                creditsDelta: -amount,
                note: note
            ),
            at: 0
        )
        return true
    }

    /// クレジットを付与する。
    func grant(_ amount: Int, note: String) {
        ledger.insert(
            UsageLedgerEntry(creditsDelta: amount, note: note),
            at: 0
        )
    }

    /// テスト・プレビュー用に台帳を差し替える。
    func replace(ledger entries: [UsageLedgerEntry]) {
        ledger = entries
    }
}
