import Foundation
import CoreData

@objc(Project)
public class Project: NSManagedObject {

    /// Inserts a new project with safe defaults already applied. Callers are
    /// still responsible for assigning it to the correct persistent store via
    /// `StoreRouter` (owners → private store).
    @discardableResult
    public static func make(in context: NSManagedObjectContext,
                            name: String,
                            ownerDisplayName: String,
                            color: ProjectColor = .olive,
                            isSample: Bool = false,
                            defaultMode: TrackingMode = .quantity) -> Project {
        let project = Project(context: context)
        let now = Date()
        project.id = UUID()
        project.name = name
        project.note = ""
        project.colorKey = color.rawValue
        project.createdAt = now
        project.updatedAt = now
        project.ownerDisplayName = ownerDisplayName
        project.isSample = isSample
        project.defaultTrackingModeRaw = defaultMode.rawValue
        return project
    }
}

extension Project {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Project> {
        NSFetchRequest<Project>(entityName: "Project")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var note: String?
    @NSManaged public var colorKey: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var archivedAt: Date?
    @NSManaged public var ownerDisplayName: String?
    @NSManaged public var isSample: Bool
    @NSManaged public var isPinned: Bool
    @NSManaged public var sortIndex: Int64
    @NSManaged public var defaultTrackingModeRaw: String?

    @NSManaged public var folders: NSSet?
    @NSManaged public var products: NSSet?
    @NSManaged public var locations: NSSet?
    @NSManaged public var events: NSSet?
    @NSManaged public var labels: NSSet?
    @NSManaged public var units: NSSet?
}

// MARK: - Typed convenience accessors

public extension Project {
    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("名称未設定のプロジェクト", comment: "") : trimmed
    }

    var color: ProjectColor {
        get { ProjectColor(raw: colorKey) }
        set { colorKey = newValue.rawValue }
    }

    /// The tracking mode pre-selected when adding a new product to this project.
    /// A convenience default only — individual products may still use any mode.
    var defaultTrackingMode: TrackingMode {
        get { TrackingMode(raw: defaultTrackingModeRaw) }
        set { defaultTrackingModeRaw = newValue.rawValue }
    }

    var isArchived: Bool { archivedAt != nil }

    var folderArray: [Folder] {
        (folders as? Set<Folder> ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }
    var productArray: [Product] {
        (products as? Set<Product> ?? []).sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    var locationArray: [Location] {
        (locations as? Set<Location> ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }
    var eventArray: [InventoryEvent] {
        (events as? Set<InventoryEvent> ?? []).sorted { ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast) }
    }
    var labelArray: [CodeAlias] {
        (labels as? Set<CodeAlias> ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// Count of active (non-archived) products.
    var activeProductCount: Int { productArray.filter { !$0.isArchived }.count }

    /// Count of products at or below their minimum stock threshold.
    var lowStockCount: Int {
        productArray.filter { !$0.isArchived && $0.isLowStock }.count
    }

    func touch() { updatedAt = Date() }
}

// MARK: - Generated accessors

extension Project {
    @objc(addFoldersObject:) @NSManaged public func addToFolders(_ value: Folder)
    @objc(removeFoldersObject:) @NSManaged public func removeFromFolders(_ value: Folder)
    @objc(addFolders:) @NSManaged public func addToFolders(_ values: NSSet)
    @objc(removeFolders:) @NSManaged public func removeFromFolders(_ values: NSSet)

    @objc(addProductsObject:) @NSManaged public func addToProducts(_ value: Product)
    @objc(removeProductsObject:) @NSManaged public func removeFromProducts(_ value: Product)

    @objc(addLocationsObject:) @NSManaged public func addToLocations(_ value: Location)
    @objc(removeLocationsObject:) @NSManaged public func removeFromLocations(_ value: Location)

    @objc(addEventsObject:) @NSManaged public func addToEvents(_ value: InventoryEvent)
    @objc(removeEventsObject:) @NSManaged public func removeFromEvents(_ value: InventoryEvent)

    @objc(addLabelsObject:) @NSManaged public func addToLabels(_ value: CodeAlias)
    @objc(removeLabelsObject:) @NSManaged public func removeFromLabels(_ value: CodeAlias)

    @objc(addUnitsObject:) @NSManaged public func addToUnits(_ value: StockUnit)
    @objc(removeUnitsObject:) @NSManaged public func removeFromUnits(_ value: StockUnit)
}

extension Project: Identifiable {}
