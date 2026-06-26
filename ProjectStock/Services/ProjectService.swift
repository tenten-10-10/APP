import Foundation
import CoreData

/// Project lifecycle: creation (with store routing), archive, duplication, and
/// the cross-project integrity check used before sharing (spec §9, §10).
struct ProjectService {

    let router: StoreRouter
    let inventory: InventoryService

    init(router: StoreRouter, inventory: InventoryService) {
        self.router = router
        self.inventory = inventory
    }

    /// Create a new, owned project in the private store.
    @discardableResult
    func createProject(name: String, ownerDisplayName: String, color: ProjectColor = .blue,
                       isSample: Bool = false, defaultMode: TrackingMode = .quantity,
                       in context: NSManagedObjectContext) -> Project {
        let project = Project.make(in: context, name: name, ownerDisplayName: ownerDisplayName,
                                   color: color, isSample: isSample, defaultMode: defaultMode)
        router.assignNewProject(project, in: context)
        return project
    }

    func archive(_ project: Project) {
        project.archivedAt = Date()
        project.touch()
    }

    func unarchive(_ project: Project) {
        project.archivedAt = nil
        project.touch()
    }

    // MARK: - Share readiness (spec §10)

    /// Verifies the project graph contains no reference to another project
    /// before we attach a CKShare. Our schema prevents cross-project
    /// relationships by construction; this is a defensive runtime check.
    func validateShareReadiness(_ project: Project) throws {
        func check(_ owner: Project?) throws {
            guard let owner, owner.objectID == project.objectID else {
                throw AppError.crossProjectReference
            }
        }
        try project.folderArray.forEach { try check($0.project) }
        try project.locationArray.forEach { try check($0.project) }
        for product in project.productArray {
            try check(product.project)
            try product.unitArray.forEach { try check($0.project) }
        }
        try project.eventArray.forEach { try check($0.project) }
        try project.labelArray.forEach { try check($0.project) }
    }

    // MARK: - Duplicate into a new project (spec §9: copy instead of cross-zone move)

    /// Deep-copy a project's structure (folders, locations, products) into a new
    /// owned project. Quantities are seeded as fresh `create` events equal to the
    /// source's current on-hand; history and labels are intentionally not copied.
    @discardableResult
    func duplicate(_ source: Project, newName: String, ownerDisplayName: String,
                   in context: NSManagedObjectContext) -> Project {
        let copy = createProject(name: newName, ownerDisplayName: ownerDisplayName,
                                 color: source.color, in: context)
        copy.note = source.note

        // Folders (preserve parent structure by id mapping).
        var folderMap: [NSManagedObjectID: Folder] = [:]
        for folder in source.folderArray.sortedByDepth(parent: \.parent) {
            let newFolder = Folder.make(in: context, name: folder.displayName, project: copy)
            newFolder.sortIndex = folder.sortIndex
            if let oldParent = folder.parent, let mapped = folderMap[oldParent.objectID] {
                newFolder.parent = mapped
            }
            router.assignChild(newFolder, toSameStoreAs: copy, in: context)
            folderMap[folder.objectID] = newFolder
        }

        // Locations.
        var locationMap: [NSManagedObjectID: Location] = [:]
        for location in source.locationArray.sortedByDepth(parent: \.parent) {
            let newLocation = Location.make(in: context, name: location.displayName, project: copy, kind: location.kind)
            newLocation.sortIndex = location.sortIndex
            newLocation.note = location.note
            if let oldParent = location.parent, let mapped = locationMap[oldParent.objectID] {
                newLocation.parent = mapped
            }
            router.assignChild(newLocation, toSameStoreAs: copy, in: context)
            locationMap[location.objectID] = newLocation
        }

        // Products with seeded quantity.
        for product in source.productArray where !product.isArchived {
            let newProduct = Product.make(in: context, name: product.displayName, project: copy,
                                          sku: product.sku ?? "", unitName: product.unitLabel,
                                          trackingMode: product.trackingMode)
            newProduct.note = product.note
            newProduct.minimumStock = product.minimumStock
            if let oldFolder = product.folder { newProduct.folder = folderMap[oldFolder.objectID] }
            if let oldLoc = product.defaultLocation { newProduct.defaultLocation = locationMap[oldLoc.objectID] }
            router.assignChild(newProduct, toSameStoreAs: copy, in: context)

            if product.trackingMode == .quantity {
                inventory.setInitialStock(product: newProduct, quantity: product.currentQuantity,
                                          location: newProduct.defaultLocation,
                                          actor: ownerDisplayName,
                                          note: NSLocalizedString("複製による初期在庫", comment: ""),
                                          in: context)
            } else if product.trackingMode == .lot {
                for lot in product.lotArray where lot.lotQuantity > 0 || lot.expiresAt != nil {
                    _ = inventory.createLot(product: newProduct, lotNumber: lot.lotNumberDisplay,
                                            quantity: lot.lotQuantity, expiresAt: lot.expiresAt,
                                            location: lot.location.flatMap { locationMap[$0.objectID] },
                                            actor: ownerDisplayName,
                                            note: NSLocalizedString("複製による初期在庫", comment: ""),
                                            in: context)
                }
            } else {
                for unit in product.unitArray where unit.status.isOnHand {
                    let newUnit = StockUnit.make(in: context, serialNumber: unit.displaySerial,
                                                 product: newProduct, project: copy,
                                                 location: unit.location.flatMap { locationMap[$0.objectID] })
                    router.assignChild(newUnit, toSameStoreAs: copy, in: context)
                    inventory.registerUnit(newUnit, location: newUnit.location, actor: ownerDisplayName, in: context)
                }
            }
        }

        return copy
    }
}

private extension Array {
    /// Order nodes so parents precede children, for safe structural copying.
    func sortedByDepth(parent: (Element) -> Element?) -> [Element] {
        func depth(_ element: Element) -> Int {
            var d = 0
            var current = parent(element)
            var guardCount = 0
            while let c = current, guardCount < 4096 { d += 1; current = parent(c); guardCount += 1 }
            return d
        }
        return sorted { depth($0) < depth($1) }
    }
}
