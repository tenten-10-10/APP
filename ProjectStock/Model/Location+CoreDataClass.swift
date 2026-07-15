import Foundation
import CoreData

@objc(Location)
public class Location: NSManagedObject {

    @discardableResult
    public static func make(in context: NSManagedObjectContext,
                            name: String,
                            project: Project,
                            kind: LocationKind = .container,
                            parent: Location? = nil) -> Location {
        let location = Location(context: context)
        let now = Date()
        location.id = UUID()
        location.name = name
        location.note = ""
        location.kindRaw = kind.rawValue
        location.sortIndex = 0
        location.createdAt = now
        location.updatedAt = now
        location.project = project
        location.parent = parent
        return location
    }
}

extension Location {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Location> {
        NSFetchRequest<Location>(entityName: "Location")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var note: String?
    @NSManaged public var kindRaw: String?
    @NSManaged public var sortIndex: Int64
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?

    @NSManaged public var project: Project?
    @NSManaged public var parent: Location?
    @NSManaged public var children: NSSet?
    @NSManaged public var products: NSSet?
    @NSManaged public var units: NSSet?
    @NSManaged public var incomingEvents: NSSet?
    @NSManaged public var outgoingEvents: NSSet?
    @NSManaged public var labels: NSSet?
}

public extension Location {
    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("名称未設定の場所", comment: "") : trimmed
    }

    var kind: LocationKind {
        get { LocationKind(raw: kindRaw) }
        set { kindRaw = newValue.rawValue }
    }

    var childArray: [Location] {
        (children as? Set<Location> ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }
    var productArray: [Product] {
        (products as? Set<Product> ?? []).sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    var unitArray: [StockUnit] {
        (units as? Set<StockUnit> ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }
    var labelArray: [CodeAlias] {
        (labels as? Set<CodeAlias> ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }
    var activeLabels: [CodeAlias] { labelArray.filter { $0.isActive } }

    /// Human-readable path from the root location, e.g. "倉庫A / 棚3 / 箱12".
    var breadcrumb: String {
        var parts: [String] = []
        var node: Location? = self
        var guardCount = 0
        while let current = node, guardCount < 64 {
            parts.insert(current.displayName, at: 0)
            node = current.parent
            guardCount += 1
        }
        return parts.joined(separator: " / ")
    }

    func touch() { updatedAt = Date() }
}

extension Location {
    @objc(addChildrenObject:) @NSManaged public func addToChildren(_ value: Location)
    @objc(removeChildrenObject:) @NSManaged public func removeFromChildren(_ value: Location)
    @objc(addProductsObject:) @NSManaged public func addToProducts(_ value: Product)
    @objc(removeProductsObject:) @NSManaged public func removeFromProducts(_ value: Product)
    @objc(addUnitsObject:) @NSManaged public func addToUnits(_ value: StockUnit)
    @objc(removeUnitsObject:) @NSManaged public func removeFromUnits(_ value: StockUnit)
    @objc(addIncomingEventsObject:) @NSManaged public func addToIncomingEvents(_ value: InventoryEvent)
    @objc(removeIncomingEventsObject:) @NSManaged public func removeFromIncomingEvents(_ value: InventoryEvent)
    @objc(addOutgoingEventsObject:) @NSManaged public func addToOutgoingEvents(_ value: InventoryEvent)
    @objc(removeOutgoingEventsObject:) @NSManaged public func removeFromOutgoingEvents(_ value: InventoryEvent)
}

extension Location: Identifiable {}
