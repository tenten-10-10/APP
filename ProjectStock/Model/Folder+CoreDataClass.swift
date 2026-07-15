import Foundation
import CoreData

@objc(Folder)
public class Folder: NSManagedObject {

    @discardableResult
    public static func make(in context: NSManagedObjectContext,
                            name: String,
                            project: Project,
                            parent: Folder? = nil) -> Folder {
        let folder = Folder(context: context)
        let now = Date()
        folder.id = UUID()
        folder.name = name
        folder.sortIndex = 0
        folder.createdAt = now
        folder.updatedAt = now
        folder.project = project
        folder.parent = parent
        return folder
    }
}

extension Folder {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Folder> {
        NSFetchRequest<Folder>(entityName: "Folder")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var sortIndex: Int64
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?

    @NSManaged public var project: Project?
    @NSManaged public var parent: Folder?
    @NSManaged public var children: NSSet?
    @NSManaged public var products: NSSet?
}

public extension Folder {
    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("名称未設定のフォルダ", comment: "") : trimmed
    }

    var childArray: [Folder] {
        (children as? Set<Folder> ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }
    var productArray: [Product] {
        (products as? Set<Product> ?? []).sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func touch() { updatedAt = Date() }
}

extension Folder {
    @objc(addChildrenObject:) @NSManaged public func addToChildren(_ value: Folder)
    @objc(removeChildrenObject:) @NSManaged public func removeFromChildren(_ value: Folder)
    @objc(addProductsObject:) @NSManaged public func addToProducts(_ value: Product)
    @objc(removeProductsObject:) @NSManaged public func removeFromProducts(_ value: Product)
}

extension Folder: Identifiable {}
