import SwiftUI

/// Captures borrower and an optional return due-date when checking a unit out
/// (貸出). On confirm it records the checkout event and (re)schedules the
/// overdue notification.
struct CheckoutSheet: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var unit: StockUnit
    var onComplete: (() -> Void)? = nil

    @State private var borrower = ""
    @State private var hasDueDate = true
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var note = ""
    @State private var error: PresentableError?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    LabeledRow(title: NSLocalizedString("対象", comment: ""), value: unit.displaySerial)
                }
                Section {
                    TextField(NSLocalizedString("借り手の名前", comment: ""), text: $borrower)
                        .accessibilityIdentifier("borrowerField")
                } header: {
                    Text(NSLocalizedString("貸出先", comment: ""))
                } footer: {
                    if borrower.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(NSLocalizedString("空欄のまま貸出すると「貸出先なし」で記録され、あとで誰に貸したか分からなくなります。", comment: ""))
                    }
                }
                Section {
                    Toggle(NSLocalizedString("返却期限を設定", comment: ""), isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker(NSLocalizedString("返却期限", comment: ""), selection: $dueDate,
                                   displayedComponents: [.date, .hourAndMinute])
                    }
                } footer: {
                    if hasDueDate {
                        Text(NSLocalizedString("期限を過ぎると通知でお知らせします。", comment: ""))
                    }
                }
                Section(NSLocalizedString("メモ", comment: "")) {
                    MultilineTextField(text: $note, placeholder: NSLocalizedString("任意", comment: ""))
                }
            }
            .navigationTitle(NSLocalizedString("貸出", comment: ""))
            .keyboardDoneBar()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("キャンセル", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("貸出する", comment: "")) { confirm() }
                        .accessibilityIdentifier("confirmCheckout")
                }
            }
            .errorAlert($error)
        }
    }

    private func confirm() {
        let unitID = unit.objectID
        let actor = settings.effectiveOperatorName
        let trimmed = borrower.trimmingCharacters(in: .whitespacesAndNewlines)
        let due: Date? = hasDueDate ? dueDate : nil
        let noteText = note
        let result = container.performWrite { ctx in
            guard let u = try ctx.existingObject(with: unitID) as? StockUnit else { return }
            container.inventory.checkout(unit: u, actor: actor,
                                         borrower: trimmed.isEmpty ? nil : trimmed,
                                         dueAt: due, note: noteText, in: ctx)
        }
        if case .failure(let err) = result { error = PresentableError(err); return }
        Haptics.success()
        // Requesting authorization is only meaningful when a due-date exists.
        if due != nil {
            NotificationService.shared.requestAuthorization { _ in
                container.refreshLoanNotifications()
            }
        } else {
            container.refreshLoanNotifications()
        }
        onComplete?()
        dismiss()
    }
}
