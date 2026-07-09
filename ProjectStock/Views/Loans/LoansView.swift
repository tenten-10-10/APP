import SwiftUI
import CoreData

/// Lists every currently checked-out unit (a loan) across all projects, with
/// overdue loans surfaced first. Supports returning a unit inline.
struct LoansView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings

    // Derive loans from the EVENT ledger (the same source the 活動 tab shows),
    // NOT a `statusRaw == checkedOut` unit fetch: a checked-out unit whose cached
    // status desynced — or whose unit↔events inverse didn't materialise on this
    // device — was silently dropped, so a loan visible in 活動 went missing here.
    // Predicate is on the event's OWN attribute (eventTypeRaw), which is safe
    // under CloudKit multi-store; relationship-traversing predicates are not.
    @FetchRequest(fetchRequest: {
        let r = InventoryEvent.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \InventoryEvent.occurredAt, ascending: false)]
        r.predicate = NSPredicate(format: "eventTypeRaw IN %@", InventoryService.statusEventTypeRaws)
        return r
    }(), animation: .default) private var statusEvents: FetchedResults<InventoryEvent>

    @State private var error: PresentableError?
    /// Loan pending the return confirmation dialog. Returning rewrites the
    /// ledger, so a mis-tap should not commit it silently.
    @State private var confirmingReturn: Loan?
    /// Loan whose deadline / borrower is being edited.
    @State private var editingLoan: Loan?

    private var loans: [Loan] {
        container.inventory.activeLoans(from: Array(statusEvents))
    }
    private var overdue: [Loan] { loans.filter(\.isOverdue).sorted { ($0.dueAt ?? .distantPast) < ($1.dueAt ?? .distantPast) } }
    private var current: [Loan] {
        loans.filter { !$0.isOverdue }.sorted { lhs, rhs in
            switch (lhs.dueAt, rhs.dueAt) {
            case let (l?, r?): return l < r
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return lhs.since < rhs.since
            }
        }
    }

    var body: some View {
        Group {
            if loans.isEmpty {
                EmptyStateView(systemImage: "checkmark.seal",
                               title: NSLocalizedString("貸出中のものはありません", comment: ""),
                               message: NSLocalizedString("個体を貸し出すと、ここで誰がいつまで借りているか確認できます。", comment: ""))
            } else {
                List {
                    if !overdue.isEmpty {
                        Section {
                            ForEach(overdue) { loanRow($0) }
                        } header: {
                            Label(NSLocalizedString("期限超過", comment: ""), systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                        }
                    }
                    Section(NSLocalizedString("貸出中", comment: "")) {
                        ForEach(current) { loanRow($0) }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(NSLocalizedString("貸出中", comment: ""))
        .confirmationDialog(NSLocalizedString("返却を記録しますか？", comment: ""),
                            isPresented: Binding(get: { confirmingReturn != nil },
                                                 set: { if !$0 { confirmingReturn = nil } }),
                            titleVisibility: .visible) {
            Button(NSLocalizedString("返却する", comment: "")) {
                if let loan = confirmingReturn { returnLoan(loan) }
                confirmingReturn = nil
            }
            Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) { confirmingReturn = nil }
        } message: {
            if let loan = confirmingReturn {
                Text(String(format: NSLocalizedString("%@（%@）を返却済みにします。", comment: ""),
                            loan.unit.displaySerial, loan.borrowerDisplay))
            }
        }
        .sheet(item: $editingLoan) { loan in
            LoanEditSheet(unit: loan.unit)
        }
        .errorAlert($error)
    }

    @ViewBuilder private func loanRow(_ loan: Loan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(loan.unit.displaySerial).font(.headline).lineLimit(1)
                Spacer()
                if loan.isOverdue { OverdueChip() }
                else if loan.isDueSoon { DueSoonChip() }
            }
            if let product = loan.unit.product {
                Text(product.displayName).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle").font(.caption2)
                Text(loan.borrowerDisplay)
            }.font(.caption).foregroundColor(.secondary)
            HStack(spacing: 6) {
                Text(String(format: NSLocalizedString("貸出: %@", comment: ""), DateFormatters.dateTime.string(from: loan.since)))
                if let due = loan.dueAt {
                    Text("·")
                    Text(String(format: NSLocalizedString("期限: %@", comment: ""), DateFormatters.dateTime.string(from: due)))
                        .foregroundColor(loan.isOverdue ? .red : (loan.isDueSoon ? .orange : .secondary))
                    if loan.isOverdue, let days = overdueDays(due), days > 0 {
                        Text(String(format: NSLocalizedString("%d日超過", comment: ""), days))
                            .foregroundColor(.red).fontWeight(.semibold)
                    }
                }
            }
            .font(.caption2).foregroundColor(.secondary)
            // A visible return button: swipe actions are invisible to many
            // non-technical users, and returning is THE core action here.
            if container.sharing.canEdit(loan.unit.project) {
                HStack(spacing: 8) {
                    Button {
                        confirmingReturn = loan
                    } label: {
                        Label(NSLocalizedString("返却する", comment: ""), systemImage: "arrow.uturn.left")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    // 「もう1週間」「名前を打ち間違えた」「期限を付け忘れた」を
                    // その場で直せる（従来は訂正→再貸出しかなく貸出日が消えた）。
                    Button {
                        editingLoan = loan
                    } label: {
                        Label(loan.dueAt == nil
                                ? NSLocalizedString("期限を設定", comment: "")
                                : NSLocalizedString("変更", comment: ""),
                              systemImage: "calendar.badge.clock")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            if container.sharing.canEdit(loan.unit.project) {
                Button {
                    confirmingReturn = loan
                } label: {
                    Label(NSLocalizedString("返却", comment: ""), systemImage: "arrow.uturn.left")
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .leading) {
            if container.sharing.canEdit(loan.unit.project) {
                Button {
                    editingLoan = loan
                } label: {
                    Label(NSLocalizedString("期限・借り手を変更", comment: ""), systemImage: "calendar.badge.clock")
                }
                .tint(.orange)
            }
        }
    }

    private func overdueDays(_ due: Date) -> Int? {
        Calendar.current.dateComponents([.day], from: due, to: Date()).day
    }

    private func returnLoan(_ loan: Loan) {
        if let project = loan.unit.project, !container.sharing.canEdit(project) {
            error = PresentableError(AppError.readOnlyProject); return
        }
        let unitID = loan.unit.objectID
        let actor = settings.effectiveOperatorName
        let result = container.performWrite { ctx in
            guard let u = try ctx.existingObject(with: unitID) as? StockUnit else { return }
            container.inventory.returnUnit(u, to: u.location, actor: actor, in: ctx)
        }
        if case .failure(let err) = result { error = PresentableError(err); return }
        Haptics.success()
        container.refreshLoanNotifications()
    }
}

/// Small red "overdue" pill.
struct OverdueChip: View {
    var body: some View {
        Text(NSLocalizedString("期限超過", comment: ""))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.red.opacity(0.15)))
            .foregroundColor(.red)
            .accessibilityLabel(Text(NSLocalizedString("期限超過", comment: "")))
    }
}

/// Small orange "due soon" pill — flags loans due within ~48h so they can be
/// triaged before they turn into overdue ones.
struct DueSoonChip: View {
    var body: some View {
        Text(NSLocalizedString("まもなく期限", comment: ""))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.orange.opacity(0.15)))
            .foregroundColor(.orange)
            .accessibilityLabel(Text(NSLocalizedString("まもなく期限", comment: "")))
    }
}

/// Reusable read-only loan summary rows (borrower / dates), used on the scan
/// result and product detail screens.
struct LoanDetailRows: View {
    let loan: Loan
    var body: some View {
        LabeledRow(title: NSLocalizedString("貸出先", comment: ""), value: loan.borrowerDisplay)
        LabeledRow(title: NSLocalizedString("貸出日時", comment: ""), value: DateFormatters.dateTime.string(from: loan.since))
        if let due = loan.dueAt {
            HStack {
                Text(NSLocalizedString("返却期限", comment: ""))
                Spacer()
                Text(DateFormatters.dateTime.string(from: due))
                    .foregroundColor(loan.isOverdue ? .red : .secondary)
                if loan.isOverdue { OverdueChip() }
            }
        }
    }
}
