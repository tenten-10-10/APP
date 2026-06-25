import SwiftUI
import CoreData

/// Lists every currently checked-out unit (a loan) across all projects, with
/// overdue loans surfaced first. Supports returning a unit inline.
struct LoansView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \StockUnit.updatedAt, ascending: true)],
        predicate: NSPredicate(format: "statusRaw == %@", UnitStatus.checkedOut.rawValue),
        animation: .default
    ) private var checkedOutUnits: FetchedResults<StockUnit>

    @State private var error: PresentableError?

    private var loans: [Loan] {
        checkedOutUnits.compactMap { container.inventory.currentLoan(for: $0) }
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
        .errorAlert($error)
    }

    @ViewBuilder private func loanRow(_ loan: Loan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(loan.unit.displaySerial).font(.headline).lineLimit(1)
                Spacer()
                if loan.isOverdue { OverdueChip() }
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
                        .foregroundColor(loan.isOverdue ? .red : .secondary)
                }
            }
            .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            if container.sharing.canEdit(loan.unit.project) {
                Button {
                    returnLoan(loan)
                } label: {
                    Label(NSLocalizedString("返却", comment: ""), systemImage: "arrow.uturn.left")
                }
                .tint(.green)
            }
        }
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
