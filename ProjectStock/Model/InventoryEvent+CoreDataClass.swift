import Foundation
import CoreData

@objc(InventoryEvent)
public class InventoryEvent: NSManagedObject {
    // Events are append-only. Construction goes through `InventoryService`,
    // which is the only place business fields should be set. After insertion,
    // the Service layer treats the business fields as immutable.
}

extension InventoryEvent {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<InventoryEvent> {
        NSFetchRequest<InventoryEvent>(entityName: "InventoryEvent")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var eventTypeRaw: String?
    @NSManaged public var quantityDelta: Double
    @NSManaged public var occurredAt: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var actorDisplayName: String?
    @NSManaged public var actorDeviceID: String?
    @NSManaged public var note: String?
    @NSManaged public var isCorrection: Bool
    @NSManaged public var borrowerName: String?
    @NSManaged public var dueAt: Date?

    @NSManaged public var project: Project?
    @NSManaged public var product: Product?
    @NSManaged public var unit: StockUnit?
    @NSManaged public var sourceLocation: Location?
    @NSManaged public var destinationLocation: Location?
    @NSManaged public var correctsEvent: InventoryEvent?
    @NSManaged public var correctedByEvents: NSSet?
}

public extension InventoryEvent {
    var eventType: InventoryEventType {
        get { InventoryEventType(raw: eventTypeRaw) }
        set { eventTypeRaw = newValue.rawValue }
    }

    var actorName: String {
        let trimmed = (actorDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("不明な操作者", comment: "") : trimmed
    }

    /// The borrower recorded on a checkout event, or `nil` when none was given.
    var borrower: String? {
        let trimmed = (borrowerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var correctionArray: [InventoryEvent] {
        (correctedByEvents as? Set<InventoryEvent> ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// Stable tiebreaker used when two events share an `occurredAt`. We compare
    /// `createdAt` then the id string so conflict resolution is deterministic
    /// across devices.
    var orderingKey: (Date, Date, String) {
        (occurredAt ?? .distantPast, createdAt ?? .distantPast, id?.uuidString ?? "")
    }
}

extension InventoryEvent {
    @objc(addCorrectedByEventsObject:) @NSManaged public func addToCorrectedByEvents(_ value: InventoryEvent)
    @objc(removeCorrectedByEventsObject:) @NSManaged public func removeFromCorrectedByEvents(_ value: InventoryEvent)
}

extension InventoryEvent: Identifiable {}
