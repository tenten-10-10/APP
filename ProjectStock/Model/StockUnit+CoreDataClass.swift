import Foundation
import CoreData

@objc(StockUnit)
public class StockUnit: NSManagedObject {

    @discardableResult
    public static func make(in context: NSManagedObjectContext,
                            serialNumber: String,
                            product: Product,
                            project: Project,
                            location: Location? = nil) -> StockUnit {
        let unit = StockUnit(context: context)
        let now = Date()
        unit.id = UUID()
        unit.serialNumber = serialNumber
        unit.kindRaw = UnitKind.serial.rawValue
        unit.lotNumber = ""
        unit.cachedQuantity = 0
        unit.statusRaw = UnitStatus.available.rawValue
        unit.note = ""
        unit.createdAt = now
        unit.updatedAt = now
        unit.product = product
        unit.project = project
        unit.location = location
        return unit
    }

    /// Create a lot (batch) unit carrying its own quantity and optional expiry.
    @discardableResult
    public static func makeLot(in context: NSManagedObjectContext,
                               lotNumber: String,
                               product: Product,
                               project: Project,
                               location: Location? = nil,
                               expiresAt: Date? = nil) -> StockUnit {
        let unit = StockUnit(context: context)
        let now = Date()
        unit.id = UUID()
        unit.serialNumber = ""
        unit.kindRaw = UnitKind.lot.rawValue
        unit.lotNumber = lotNumber
        unit.expiresAt = expiresAt
        unit.cachedQuantity = 0
        unit.statusRaw = UnitStatus.available.rawValue
        unit.note = ""
        unit.createdAt = now
        unit.updatedAt = now
        unit.product = product
        unit.project = project
        unit.location = location
        return unit
    }
}

extension StockUnit {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<StockUnit> {
        NSFetchRequest<StockUnit>(entityName: "StockUnit")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var serialNumber: String?
    @NSManaged public var kindRaw: String?
    @NSManaged public var lotNumber: String?
    @NSManaged public var expiresAt: Date?
    @NSManaged public var cachedQuantity: Double
    @NSManaged public var statusRaw: String?
    @NSManaged public var note: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?

    @NSManaged public var product: Product?
    @NSManaged public var project: Project?
    @NSManaged public var location: Location?
    @NSManaged public var events: NSSet?
    @NSManaged public var labels: NSSet?
}

public extension StockUnit {
    var displaySerial: String {
        let trimmed = (serialNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("シリアル未設定", comment: "") : trimmed
    }

    var status: UnitStatus {
        get { UnitStatus(raw: statusRaw) }
        set { statusRaw = newValue.rawValue }
    }

    var kind: UnitKind {
        get { UnitKind(raw: kindRaw) }
        set { kindRaw = newValue.rawValue }
    }

    var isLot: Bool { kind == .lot }

    var lotNumberDisplay: String {
        let trimmed = (lotNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("ロット番号未設定", comment: "") : trimmed
    }

    /// Serial number for serial units, lot number for lots.
    var displayTitle: String { isLot ? lotNumberDisplay : displaySerial }

    /// Current on-hand quantity for a lot (rebuilt from the ledger by
    /// `InventoryService`). Serial units are implicitly one when on hand.
    var lotQuantity: Double { cachedQuantity }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }

    /// `true` when the lot expires within `days` and is not already expired.
    func expiresSoon(within days: Int = 30) -> Bool {
        guard let expiresAt, !isExpired else { return false }
        let threshold = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return expiresAt <= threshold
    }

    var eventArray: [InventoryEvent] {
        (events as? Set<InventoryEvent> ?? []).sorted { ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast) }
    }
    var labelArray: [CodeAlias] {
        (labels as? Set<CodeAlias> ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }
    var activeLabels: [CodeAlias] { labelArray.filter { $0.isActive } }

    func touch() { updatedAt = Date() }
}

extension StockUnit {
    @objc(addEventsObject:) @NSManaged public func addToEvents(_ value: InventoryEvent)
    @objc(removeEventsObject:) @NSManaged public func removeFromEvents(_ value: InventoryEvent)
    @objc(addLabelsObject:) @NSManaged public func addToLabels(_ value: CodeAlias)
    @objc(removeLabelsObject:) @NSManaged public func removeFromLabels(_ value: CodeAlias)
}

extension StockUnit: Identifiable {}
