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
