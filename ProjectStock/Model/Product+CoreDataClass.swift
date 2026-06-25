import Foundation
import CoreData

@objc(Product)
public class Product: NSManagedObject {

    @discardableResult
    public static func make(in context: NSManagedObjectContext,
                            name: String,
                            project: Project,
                            sku: String = "",
                            unitName: String = "pcs",
                            trackingMode: TrackingMode = .quantity,
                            folder: Folder? = nil) -> Product {
        let product = Product(context: context)
        let now = Date()
        product.id = UUID()
        product.name = name
        product.sku = sku
        product.note = ""
        product.unitName = unitName
        product.trackingModeRaw = trackingMode.rawValue
        product.minimumStock = 0
        product.cachedQuantity = 0
        product.isArchived = false
        product.createdAt = now
        product.updatedAt = now
        product.project = project
        product.folder = folder
        return product
    }
}

extension Product {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Product> {
        NSFetchRequest<Product>(entityName: "Product")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var sku: String?
    @NSManaged public var note: String?
    @NSManaged public var unitName: String?
    @NSManaged public var trackingModeRaw: String?
    @NSManaged public var minimumStock: Double
    @NSManaged public var cachedQuantity: Double
    @NSManaged public var isArchived: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var photoData: Data?

    @NSManaged public var project: Project?
    @NSManaged public var folder: Folder?
    @NSManaged public var defaultLocation: Location?
    @NSManaged public var units: NSSet?
    @NSManaged public var events: NSSet?
    @NSManaged public var labels: NSSet?
}

public extension Product {
    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("名称未設定の製品", comment: "") : trimmed
    }

    var trackingMode: TrackingMode {
        get { TrackingMode(raw: trackingModeRaw) }
        set { trackingModeRaw = newValue.rawValue }
    }

    var unitLabel: String {
        let trimmed = (unitName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "pcs" : trimmed
    }

    var unitArray: [StockUnit] {
        (units as? Set<StockUnit> ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }
    var eventArray: [InventoryEvent] {
        (events as? Set<InventoryEvent> ?? []).sorted { ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast) }
    }
    var labelArray: [CodeAlias] {
        (labels as? Set<CodeAlias> ?? [])
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }
    var activeLabels: [CodeAlias] { labelArray.filter { $0.isActive } }

    /// Display quantity. For individual-tracking products this counts on-hand
    /// units; otherwise it returns the cached running total (which is rebuilt
    /// from the ledger by `InventoryService`).
    var currentQuantity: Double {
        switch trackingMode {
        case .quantity, .lot:
            return cachedQuantity
        case .individual:
            return Double(unitArray.filter { $0.status.isOnHand }.count)
        }
    }

    /// Lots (batch units) sorted by soonest expiry, then creation. Only
    /// meaningful for `.lot` products.
    var lotArray: [StockUnit] {
        unitArray.filter { $0.isLot }.sorted { lhs, rhs in
            switch (lhs.expiresAt, rhs.expiresAt) {
            case let (l?, r?): return l < r
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
            }
        }
    }

    var isLowStock: Bool {
        guard minimumStock > 0 else { return false }
        return currentQuantity <= minimumStock
    }

    /// Most recent event that touched this product, across all types.
    var lastEvent: InventoryEvent? { eventArray.first }

    /// Best-effort "where is it now": the destination of the most recent event
    /// that carried a location, falling back to the default location.
    var currentLocation: Location? {
        for event in eventArray {
            if let dest = event.destinationLocation { return dest }
            if let src = event.sourceLocation { return src }
        }
        return defaultLocation
    }

    func touch() { updatedAt = Date() }
}

extension Product {
    @objc(addUnitsObject:) @NSManaged public func addToUnits(_ value: StockUnit)
    @objc(removeUnitsObject:) @NSManaged public func removeFromUnits(_ value: StockUnit)
    @objc(addEventsObject:) @NSManaged public func addToEvents(_ value: InventoryEvent)
    @objc(removeEventsObject:) @NSManaged public func removeFromEvents(_ value: InventoryEvent)
    @objc(addLabelsObject:) @NSManaged public func addToLabels(_ value: CodeAlias)
    @objc(removeLabelsObject:) @NSManaged public func removeFromLabels(_ value: CodeAlias)
}

extension Product: Identifiable {}
