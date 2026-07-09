import SwiftUI
import CoreData

/// Edit the CURRENT loan of a checked-out unit: fix the borrower name, extend
/// (or first set) the return deadline. Updates the establishing checkout event
/// in place so 「いつから借りているか」 is preserved — the 訂正→再貸出 detour
/// resets the loan date and loses that continuity.
struct LoanEditSheet: View {
    @EnvironmentObject private var container: ServiceContainer
    @Environment(\.dismiss) private var dismiss

    let unit: StockUnit

    @State private var borrower = ""
    @State private var hasDue = false
    @State private var due = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var error: PresentableError?

    /// 返却期限は日単位（その日の終わり=23:59まで）に統一する。
    private func endOfDay(_ date: Date) -> Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
    }

    var body: some View {
        NavigationView {
            Form {
                Section(NSLocalizedString("借り手", comment: "")) {
                    TextField(NSLocalizedString("名前（例: 山田）", comment: ""), text: $borrower)
                        .accessibilityIdentifier("loanBorrowerField")
                }
                Section {
                    Toggle(NSLocalizedString("返却期限", comment: ""), isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker(NSLocalizedString("期限", comment: ""), selection: $due,
                                   displayedComponents: [.date])
                    }
                } footer: {
                    Text(NSLocalizedString("その日の終わり（23:59）を期限とし、過ぎたときに通知でお知らせします。貸出日はそのまま保持されます。", comment: ""))
                }
            }
            .navigationTitle(NSLocalizedString("貸出内容を変更", comment: ""))
            .keyboardDoneBar()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("キャンセル", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("保存", comment: "")) { save() }
                }
            }
            .onAppear(perform: load)
            .errorAlert($error)
        }
    }

    private func load() {
        guard let loan = container.inventory.currentLoan(for: unit) else { return }
        borrower = loan.borrower ?? ""
        if let dueAt = loan.dueAt {
            hasDue = true
            due = dueAt
        }
    }

    private func save() {
        let unitID = unit.objectID
        let name = borrower
        let dueAt: Date? = hasDue ? endOfDay(due) : nil
        let result = container.performWrite { ctx in
            guard let u = try ctx.existingObject(with: unitID) as? StockUnit else { return }
            guard container.inventory.updateLoan(for: u, borrower: name, dueAt: dueAt) else {
                throw AppError.underlying(NSLocalizedString("この個体は貸出中ではありません。", comment: ""))
            }
        }
        switch result {
        case .success:
            Haptics.success()
            if dueAt != nil {
                NotificationService.shared.requestAuthorization { _ in
                    container.refreshLoanNotifications()
                }
            } else {
                container.refreshLoanNotifications()
            }
            dismiss()
        case .failure(let err):
            error = PresentableError(err)
        }
    }
}
