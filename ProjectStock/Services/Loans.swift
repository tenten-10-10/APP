import Foundation
import CoreData

/// A snapshot of an active loan: a unit that is currently checked out, plus the
/// borrower / dates derived from its establishing checkout event.
struct Loan: Identifiable {
    let unit: StockUnit
    let event: InventoryEvent
    let borrower: String?
    let since: Date
    let dueAt: Date?

    var id: NSManagedObjectID { unit.objectID }

    var isOverdue: Bool {
        guard let dueAt else { return false }
        return dueAt < Date()
    }

    var borrowerDisplay: String {
        borrower ?? NSLocalizedString("借り手未記入", comment: "")
    }

    /// Primitive snapshot for scheduling — call on the unit's context queue.
    var notice: LoanNotice? {
        guard let due = dueAt, let unitID = unit.id else { return nil }
        let who = borrower ?? NSLocalizedString("借り手", comment: "")
        return LoanNotice(
            identifier: NotificationService.loanIdentifier(unitID: unitID),
            title: NSLocalizedString("貸出期限", comment: ""),
            body: String(format: NSLocalizedString("「%@」の返却期限です（貸出先: %@）", comment: ""),
                         unit.displaySerial, who),
            due: due
        )
    }
}

extension InventoryService {

    /// The loan currently in effect for a unit, or `nil` if it is not checked
    /// out. The establishing event is the most recent, non-corrected checkout.
    func currentLoan(for unit: StockUnit) -> Loan? {
        guard resolvedStatus(for: unit) == .checkedOut else { return nil }
        let checkout = unit.eventArray
            .filter { $0.eventType == .checkout && $0.correctionArray.isEmpty }
            .max(by: { $0.orderingKey < $1.orderingKey })
        guard let event = checkout else { return nil }
        return Loan(unit: unit, event: event, borrower: event.borrower,
                    since: event.occurredAt ?? event.createdAt ?? Date(), dueAt: event.dueAt)
    }

    /// All active loans reachable in a context, ordered overdue/soonest-due
    /// first, then by borrow time.
    func activeLoans(in context: NSManagedObjectContext) -> [Loan] {
        let request = StockUnit.fetchRequest()
        request.predicate = NSPredicate(format: "statusRaw == %@", UnitStatus.checkedOut.rawValue)
        let units = (try? context.fetch(request)) ?? []
        return units.compactMap { currentLoan(for: $0) }.sorted { lhs, rhs in
            switch (lhs.dueAt, rhs.dueAt) {
            case let (l?, r?): return l < r          // soonest due first
            case (_?, nil):    return true           // dated loans before undated
            case (nil, _?):    return false
            case (nil, nil):   return lhs.since < rhs.since
            }
        }
    }
}
