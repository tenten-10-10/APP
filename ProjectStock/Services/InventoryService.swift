import Foundation
import CoreData

/// The append-only inventory ledger (spec §4.4, §11). All stock changes flow
/// through here as immutable `InventoryEvent`s; quantity caches are derived,
/// never authoritative. Corrections are made by adding reversing / correction
/// events, never by editing history.
struct InventoryService {

    let device: DeviceIdentity
    let router: StoreRouter

    init(device: DeviceIdentity, router: StoreRouter) {
        self.device = device
        self.router = router
    }

    // MARK: - Quantity-mode operations

    /// Initial stock for a freshly created product.
    @discardableResult
    func setInitialStock(product: Product, quantity: Double, location: Location?,
                         actor: String, note: String = "",
                         occurredAt: Date = Date(),
                         in context: NSManagedObjectContext) -> InventoryEvent {
        let event = makeEvent(type: .create, product: product, unit: nil,
                              delta: quantity, source: nil, destination: location,
                              actor: actor, note: note, occurredAt: occurredAt,
                              isCorrection: false, corrects: nil, in: context)
        recompute(product: product)
        return event
    }

    /// Receive stock (入庫).
    @discardableResult
    func receive(product: Product, quantity: Double, location: Location?,
                 actor: String, note: String = "", occurredAt: Date = Date(),
                 in context: NSManagedObjectContext) -> InventoryEvent {
        let event = makeEvent(type: .receive, product: product, unit: nil,
                              delta: abs(quantity), source: nil, destination: location,
                              actor: actor, note: note, occurredAt: occurredAt,
                              isCorrection: false, corrects: nil, in: context)
        recompute(product: product)
        return event
    }

    /// Consume / issue stock (消費・出庫).
    @discardableResult
    func consume(product: Product, quantity: Double, location: Location?,
                 actor: String, note: String = "", occurredAt: Date = Date(),
                 in context: NSManagedObjectContext) -> InventoryEvent {
        let event = makeEvent(type: .consume, product: product, unit: nil,
                              delta: -abs(quantity), source: location, destination: nil,
                              actor: actor, note: note, occurredAt: occurredAt,
                              isCorrection: false, corrects: nil, in: context)
        recompute(product: product)
        return event
    }

    /// Stocktake adjustment to an absolute counted quantity. Records an `adjust`
    /// event whose delta closes the gap between ledger total and the count.
    @discardableResult
    func adjust(product: Product, toCountedQuantity counted: Double, location: Location?,
                actor: String, note: String = "", occurredAt: Date = Date(),
                in context: NSManagedObjectContext) -> InventoryEvent {
        let current = ledgerQuantity(for: product)
        let delta = counted - current
        let event = makeEvent(type: .adjust, product: product, unit: nil,
                              delta: delta, source: nil, destination: location,
                              actor: actor, note: note, occurredAt: occurredAt,
                              isCorrection: false, corrects: nil, in: context)
        recompute(product: product)
        return event
    }

    /// Move a quantity between locations (場所移動). Does not change the total.
    @discardableResult
    func transferQuantity(product: Product, quantity: Double, from: Location?, to: Location?,
                          actor: String, note: String = "", occurredAt: Date = Date(),
                          in context: NSManagedObjectContext) -> InventoryEvent {
        let event = makeEvent(type: .transfer, product: product, unit: nil,
                              delta: abs(quantity), source: from, destination: to,
                              actor: actor, note: note, occurredAt: occurredAt,
                              isCorrection: false, corrects: nil, in: context)
        recompute(product: product)
        return event
    }

    // MARK: - Individual-mode (StockUnit) operations

    @discardableResult
    func registerUnit(_ unit: StockUnit, location: Location?, actor: String,
                      note: String = "", occurredAt: Date = Date(),
                      in context: NSManagedObjectContext) -> InventoryEvent {
        unit.location = location
        unit.status = .available
        unit.touch()
        let event = makeEvent(type: .create, product: unit.product, unit: unit,
                              delta: 1, source: nil, destination: location,
                              actor: actor, note: note, occurredAt: occurredAt,
                              isCorrection: false, corrects: nil, in: context)
        if let product = unit.product { recompute(product: product) }
        return event
    }

    @discardableResult
    func checkout(unit: StockUnit, actor: String, note: String = "",
                  occurredAt: Date = Date(), in context: NSManagedObjectContext) -> InventoryEvent {
        let from = unit.location
        unit.status = .checkedOut
        unit.touch()
        let event = makeEvent(type: .checkout, product: unit.product, unit: unit,
                              delta: 0, source: from, destination: nil,
                              actor: actor, note: note, occurredAt: occurredAt,
                              isCorrection: false, corrects: nil, in: context)
        if let product = unit.product { recompute(product: product) }
        return event
    }

    @discardableResult
    func returnUnit(_ unit: StockUnit, to location: Location?, actor: String, note: String = "",
                    occurredAt: Date = Date(), in context: NSManagedObjectContext) -> InventoryEvent {
        unit.status = .available
        unit.location = location ?? unit.location
        unit.touch()
        let event = makeEvent(type: .returned, product: unit.product, unit: unit,
                              delta: 0, source: nil, destination: unit.location,
                              actor: actor, note: note, occurredAt: occurredAt,
                              isCorrection: false, corrects: nil, in: context)
        if let product = unit.product { recompute(product: product) }
        return event
    }

    @discardableResult
    func transferUnit(_ unit: StockUnit, to location: Location?, actor: String, note: String = "",
                      occurredAt: Date = Date(), in context: NSManagedObjectContext) -> InventoryEvent {
        let from = unit.location
        unit.location = location
        unit.touch()
        return makeEvent(type: .transfer, product: unit.product, unit: unit,
                         delta: 0, source: from, destination: location,
                         actor: actor, note: note, occurredAt: occurredAt,
                         isCorrection: false, corrects: nil, in: context)
    }

    @discardableResult
    func retireUnit(_ unit: StockUnit, actor: String, note: String = "",
                    occurredAt: Date = Date(), in context: NSManagedObjectContext) -> InventoryEvent {
        let from = unit.location
        unit.status = .retired
        unit.touch()
        let event = makeEvent(type: .retire, product: unit.product, unit: unit,
                              delta: 0, source: from, destination: nil,
                              actor: actor, note: note, occurredAt: occurredAt,
                              isCorrection: false, corrects: nil, in: context)
        if let product = unit.product { recompute(product: product) }
        return event
    }

    // MARK: - Corrections (append-only)

    /// Create a reversing correction for a prior event (逆仕訳). The original is
    /// left untouched; the new event negates its quantity delta and swaps
    /// source/destination, and links back via `correctsEvent`.
    ///
    /// The reversal only mirrors the quantity delta when the original event
    /// actually affected the on-hand total — otherwise a `.transfer` (which
    /// moves location but not stock) would be subtracted from the total. For
    /// unit status events, the unit's status is restored once the original is
    /// marked corrected.
    @discardableResult
    func reverse(event original: InventoryEvent, actor: String, note: String,
                 occurredAt: Date = Date(), in context: NSManagedObjectContext) -> InventoryEvent {
        let reversalDelta = original.eventType.affectsQuantityTotal ? -original.quantityDelta : 0
        let event = makeEvent(type: .correction, product: original.product, unit: original.unit,
                              delta: reversalDelta,
                              source: original.destinationLocation,
                              destination: original.sourceLocation,
                              actor: actor, note: note, occurredAt: occurredAt,
                              isCorrection: true, corrects: original, in: context)
        // The original is now linked as corrected, so status resolution will
        // ignore it and fall back to the previous status event.
        if let unit = original.unit { applyResolvedStatus(to: unit) }
        if let product = original.product { recompute(product: product) }
        return event
    }

    // MARK: - Recomputation (cache rebuild, spec §11)

    /// Sum of quantity-affecting deltas in the ledger for a product.
    func ledgerQuantity(for product: Product) -> Double {
        product.eventArray
            .filter { $0.eventType.affectsQuantityTotal }
            .reduce(0.0) { $0 + $1.quantityDelta }
    }

    /// Rebuild a single product's cached quantity from its ledger.
    func recompute(product: Product) {
        switch product.trackingMode {
        case .quantity:
            product.cachedQuantity = ledgerQuantity(for: product)
        case .individual:
            product.cachedQuantity = Double(product.unitArray.filter { $0.status.isOnHand }.count)
        }
        product.updatedAt = Date()
    }

    /// Rebuild every product in a project (app launch / remote change, spec §11).
    func recomputeAll(in project: Project) {
        for product in project.productArray {
            // Re-derive each individually-tracked unit's status from its ledger
            // first so conflicts settle deterministically before caching.
            if product.trackingMode == .individual {
                for unit in product.unitArray { applyResolvedStatus(to: unit) }
            }
            recompute(product: product)
        }
    }

    // MARK: - Unit conflict resolution (spec §11 個体管理モード)

    /// The status implied by the most recent status-changing event, using a
    /// stable tiebreaker (occurredAt, then createdAt, then id) so two devices
    /// converge on the same answer. Events that have since been corrected
    /// (reversed) are ignored, so a corrected checkout/retire is undone.
    func resolvedStatus(for unit: StockUnit) -> UnitStatus {
        let statusEvents = unit.eventArray.filter {
            statusImplied(by: $0.eventType) != nil && $0.correctionArray.isEmpty
        }
        guard let latest = statusEvents.max(by: { lhs, rhs in
            lhs.orderingKey < rhs.orderingKey
        }) else {
            return unit.status
        }
        return statusImplied(by: latest.eventType) ?? unit.status
    }

    func applyResolvedStatus(to unit: StockUnit) {
        let resolved = resolvedStatus(for: unit)
        if unit.status != resolved { unit.status = resolved; unit.touch() }
    }

    /// `true` if two near-simultaneous events from different devices disagree
    /// about the unit's resulting status (drives the conflict badge in the UI).
    func hasUnresolvedConflict(for unit: StockUnit) -> Bool {
        let statusEvents = unit.eventArray
            .filter { statusImplied(by: $0.eventType) != nil }
            .sorted { $0.orderingKey > $1.orderingKey }
        guard statusEvents.count >= 2 else { return false }
        let a = statusEvents[0], b = statusEvents[1]
        let sameInstant = (a.occurredAt ?? .distantPast) == (b.occurredAt ?? .distantPast)
        let differentDevice = (a.actorDeviceID ?? "") != (b.actorDeviceID ?? "")
        let differentOutcome = statusImplied(by: a.eventType) != statusImplied(by: b.eventType)
        return sameInstant && differentDevice && differentOutcome
    }

    private func statusImplied(by type: InventoryEventType) -> UnitStatus? {
        switch type {
        case .create, .receive, .returned: return .available
        case .checkout:                  return .checkedOut
        case .consume:                   return .consumed
        case .retire:                    return .retired
        case .adjust, .transfer, .correction: return nil
        }
    }

    // MARK: - Event construction (single funnel)

    private func makeEvent(type: InventoryEventType, product: Product?, unit: StockUnit?,
                           delta: Double, source: Location?, destination: Location?,
                           actor: String, note: String, occurredAt: Date,
                           isCorrection: Bool, corrects: InventoryEvent?,
                           in context: NSManagedObjectContext) -> InventoryEvent {
        let project = product?.project ?? unit?.project ?? source?.project ?? destination?.project
        let event = InventoryEvent(context: context)
        event.id = UUID()
        event.eventType = type
        event.quantityDelta = delta
        event.occurredAt = occurredAt
        event.createdAt = Date()
        event.actorDisplayName = actor
        event.actorDeviceID = device.deviceID
        event.note = note
        event.isCorrection = isCorrection
        event.project = project
        event.product = product
        event.unit = unit
        event.sourceLocation = source
        event.destinationLocation = destination
        event.correctsEvent = corrects
        if let project { router.assignChild(event, toSameStoreAs: project, in: context) }
        return event
    }
}
