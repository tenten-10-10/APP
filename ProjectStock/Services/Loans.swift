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

    /// Due within the next 48 hours (and not already overdue). Lets the loans
    /// list flag "today / soon" items for triage instead of only turning red
    /// once the deadline has already passed.
    var isDueSoon: Bool {
        guard let dueAt, !isOverdue else { return false }
        return dueAt < Date().addingTimeInterval(48 * 60 * 60)
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
    /// out. Derived purely from the unit's event ledger (the same source the
    /// 活動 tab shows): the unit is on loan iff its latest non-corrected,
    /// status-changing event is a checkout. This intentionally does NOT gate on
    /// `unit.status` — a cached status that desynced (or an earlier two-step
    /// lookup that disagreed with itself) must not make a live loan disappear.
    func currentLoan(for unit: StockUnit) -> Loan? {
        guard let checkout = openCheckout(among: unit.eventArray) else { return nil }
        return loan(from: checkout, unit: unit)
    }

    /// All active loans reachable in a context, ordered soonest-due first. Built
    /// from the EVENT ledger (reaching each unit via `event.unit`) rather than a
    /// `statusRaw == checkedOut` unit fetch, so a loan still lists even when the
    /// unit↔events inverse relationship hasn't materialised on this device or the
    /// unit's cached status desynced — the case where a loan shows in 活動 but was
    /// missing from the loans list (the reported "紐付け" bug).
    func activeLoans(in context: NSManagedObjectContext) -> [Loan] {
        let request = InventoryEvent.fetchRequest()
        request.predicate = NSPredicate(format: "eventTypeRaw IN %@", Self.statusEventTypeRaws)
        let events = (try? context.fetch(request)) ?? []
        return activeLoans(from: events)
    }

    /// Compute the currently-open loans from a flat list of events. Used by the
    /// views, which fetch events reactively (a `@FetchRequest`). Groups by unit,
    /// keeps the latest non-corrected status-changing event per unit, and emits a
    /// loan for every unit whose latest such event is a checkout.
    func activeLoans(from events: [InventoryEvent]) -> [Loan] {
        var latestByUnit: [NSManagedObjectID: InventoryEvent] = [:]
        for event in events {
            guard statusImplied(by: event.eventType) != nil,
                  event.correctionArray.isEmpty,
                  let unit = event.unit else { continue }
            if let current = latestByUnit[unit.objectID],
               !(current.orderingKey < event.orderingKey) { continue }
            latestByUnit[unit.objectID] = event
        }
        return latestByUnit.values.compactMap { event -> Loan? in
            guard event.eventType == .checkout, let unit = event.unit else { return nil }
            return loan(from: event, unit: unit)
        }
        .sorted { lhs, rhs in
            switch (lhs.dueAt, rhs.dueAt) {
            case let (l?, r?): return l < r          // soonest due first
            case (_?, nil):    return true           // dated loans before undated
            case (nil, _?):    return false
            case (nil, nil):   return lhs.since < rhs.since
            }
        }
    }

    /// Event types that change a unit's status (the ledger's "status timeline").
    static let statusEventTypeRaws: [String] = [
        InventoryEventType.create, .receive, .returned, .checkout, .consume, .retire
    ].map(\.rawValue)

    /// The latest non-corrected status-changing event among `events`, but only if
    /// it is a checkout (i.e. the unit is currently out) — else nil.
    private func openCheckout(among events: [InventoryEvent]) -> InventoryEvent? {
        let statusEvents = events.filter {
            statusImplied(by: $0.eventType) != nil && $0.correctionArray.isEmpty
        }
        guard let latest = statusEvents.max(by: { $0.orderingKey < $1.orderingKey }),
              latest.eventType == .checkout else { return nil }
        return latest
    }

    private func loan(from checkout: InventoryEvent, unit: StockUnit) -> Loan {
        Loan(unit: unit, event: checkout, borrower: checkout.borrower,
             since: checkout.occurredAt ?? checkout.createdAt ?? Date(), dueAt: checkout.dueAt)
    }

    // MARK: - Expiry lots

    /// All lot units that have a future `expiresAt` date, ordered soonest-expiry
    /// first. Used by `ServiceContainer.refreshExpiryNotifications()` to build
    /// notification payloads. Lots that are already expired are included so that
    /// outstanding (delivered) notifications can be removed; the notification
    /// service filters past dates before scheduling.
    func expiringLots(in context: NSManagedObjectContext) -> [StockUnit] {
        let request = StockUnit.fetchRequest()
        // Fetch all lots that have any expiresAt — we filter in Swift so that
        // both future and already-expired lots are covered (lets syncExpiry
        // clean up stale notifications for expired lots too).
        request.predicate = NSPredicate(format: "kindRaw == %@ AND expiresAt != nil",
                                        UnitKind.lot.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "expiresAt", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    /// Build a `LoanNotice` (reusing the same value type) for a lot's expiry
    /// date. Returns `nil` if the lot has no id or no expiry date.
    func expiryNotice(for lot: StockUnit) -> LoanNotice? {
        guard let unitID = lot.id, let expiry = lot.expiresAt else { return nil }
        let productName = lot.product?.displayName ?? NSLocalizedString("製品", comment: "")
        return LoanNotice(
            identifier: NotificationService.expiryIdentifier(unitID: unitID),
            title: NSLocalizedString("ロット有効期限", comment: ""),
            body: String(format: NSLocalizedString("「%@」ロット %@ の有効期限が近づいています。", comment: ""),
                         productName, lot.lotNumberDisplay),
            due: expiry
        )
    }
}
