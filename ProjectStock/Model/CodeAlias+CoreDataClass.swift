import Foundation
import CoreData

@objc(CodeAlias)
public class CodeAlias: NSManagedObject {

    @discardableResult
    public static func make(in context: NSManagedObjectContext,
                            publicCode: String,
                            project: Project) -> CodeAlias {
        let alias = CodeAlias(context: context)
        alias.id = UUID()
        alias.publicCode = publicCode
        alias.targetTypeRaw = CodeTargetType.unassigned.rawValue
        alias.isActive = true
        alias.createdAt = Date()
        alias.scanCount = 0
        alias.project = project
        return alias
    }
}

extension CodeAlias {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CodeAlias> {
        NSFetchRequest<CodeAlias>(entityName: "CodeAlias")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var publicCode: String?
    @NSManaged public var targetTypeRaw: String?
    @NSManaged public var isActive: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var retiredAt: Date?
    @NSManaged public var lastScannedAt: Date?
    @NSManaged public var scanCount: Int64

    @NSManaged public var project: Project?
    @NSManaged public var product: Product?
    @NSManaged public var unit: StockUnit?
    @NSManaged public var location: Location?
}

public extension CodeAlias {
    var code: String { publicCode ?? "" }

    var targetType: CodeTargetType {
        get { CodeTargetType(raw: targetTypeRaw) }
        set { targetTypeRaw = newValue.rawValue }
    }

    /// The current concrete target, if any.
    var resolvedTargetName: String {
        switch targetType {
        case .product:    return product?.displayName ?? NSLocalizedString("削除された製品", comment: "")
        case .unit:       return unit?.displaySerial ?? NSLocalizedString("削除された個体", comment: "")
        case .location:   return location?.displayName ?? NSLocalizedString("削除された場所", comment: "")
        case .unassigned: return NSLocalizedString("未割当", comment: "")
        }
    }

    func registerScan(at date: Date = Date()) {
        lastScannedAt = date
        scanCount += 1
    }
}

extension CodeAlias: Identifiable {}
