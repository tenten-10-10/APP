import Foundation
import CoreData

enum HierarchyError: LocalizedError {
    case wouldCreateCycle
    case crossProject

    var errorDescription: String? {
        switch self {
        case .wouldCreateCycle:
            return NSLocalizedString("親子関係が循環するため設定できません。", comment: "")
        case .crossProject:
            return NSLocalizedString("別のプロジェクトの項目を親に設定できません。", comment: "")
        }
    }
}

/// Folder tree operations with cycle detection (spec §5.2).
struct FolderService {

    /// Reparent a folder, rejecting moves that would create a cycle or cross a
    /// project boundary.
    func setParent(_ folder: Folder, to newParent: Folder?) throws {
        if let parent = newParent {
            guard sameProject(parent, folder) else { throw HierarchyError.crossProject }
            guard !wouldCreateCycle(moving: folder, under: parent) else { throw HierarchyError.wouldCreateCycle }
        }
        folder.parent = newParent
        folder.touch()
    }

    /// Returns true if placing `node` under `parent` would form a cycle, i.e.
    /// `parent` is `node` itself or one of its descendants.
    func wouldCreateCycle(moving node: Folder, under parent: Folder) -> Bool {
        var current: Folder? = parent
        var guardCount = 0
        while let c = current, guardCount < 4096 {
            if c.objectID == node.objectID || (c.id != nil && c.id == node.id) { return true }
            current = c.parent
            guardCount += 1
        }
        return false
    }

    private func sameProject(_ a: Folder, _ b: Folder) -> Bool {
        guard let pa = a.project, let pb = b.project else { return a.project === b.project }
        return pa.objectID == pb.objectID
    }
}

/// Location tree operations: cycle detection plus container bulk-move (spec §4.3).
struct LocationService {

    let inventory: InventoryService

    init(inventory: InventoryService) {
        self.inventory = inventory
    }

    func setParent(_ location: Location, to newParent: Location?) throws {
        if let parent = newParent {
            guard sameProject(parent, location) else { throw HierarchyError.crossProject }
            guard !wouldCreateCycle(moving: location, under: parent) else { throw HierarchyError.wouldCreateCycle }
        }
        location.parent = newParent
        location.touch()
    }

    func wouldCreateCycle(moving node: Location, under parent: Location) -> Bool {
        var current: Location? = parent
        var guardCount = 0
        while let c = current, guardCount < 4096 {
            if c.objectID == node.objectID || (c.id != nil && c.id == node.id) { return true }
            current = c.parent
            guardCount += 1
        }
        return false
    }

    /// All products & units contained in a location, including nested children.
    func contents(of container: Location, includeDescendants: Bool = true) -> (products: [Product], units: [StockUnit]) {
        var locations: [Location] = [container]
        if includeDescendants {
            var queue = container.childArray
            var guardCount = 0
            while let next = queue.first, guardCount < 100_000 {
                queue.removeFirst()
                locations.append(next)
                queue.append(contentsOf: next.childArray)
                guardCount += 1
            }
        }
        var products: [Product] = []
        var units: [StockUnit] = []
        for loc in locations {
            products.append(contentsOf: loc.productArray)
            units.append(contentsOf: loc.unitArray)
        }
        return (products, units)
    }

    /// Bulk-move everything in a container to a destination location, recording
    /// a transfer event per moved item (spec §4.3). Returns the moved counts.
    @discardableResult
    func bulkMoveContents(of container: Location, to destination: Location,
                          actor: String, in context: NSManagedObjectContext) throws -> (products: Int, units: Int) {
        guard sameProject(container, destination) else { throw HierarchyError.crossProject }
        let (products, units) = contents(of: container, includeDescendants: true)

        for product in products where product.defaultLocation?.objectID == container.objectID || isInside(product.defaultLocation, container) {
            let from = product.defaultLocation
            product.defaultLocation = destination
            product.touch()
            inventory.transferQuantity(product: product, quantity: product.currentQuantity,
                                       from: from, to: destination, actor: actor,
                                       note: NSLocalizedString("コンテナ一括移動", comment: ""),
                                       in: context)
        }
        for unit in units {
            inventory.transferUnit(unit, to: destination, actor: actor,
                                   note: NSLocalizedString("コンテナ一括移動", comment: ""),
                                   in: context)
        }
        return (products.count, units.count)
    }

    /// Delete a location together with its sub-locations (the model's Cascade
    /// rule). Inventory is never deleted with it: products / units keep
    /// existing with their location cleared (Nullify), and QR labels bound to
    /// any deleted location are released back to blank so the printed
    /// stickers stay reusable. History events keep existing with the location
    /// link cleared.
    func deleteLocation(_ location: Location, in context: NSManagedObjectContext) {
        var stack: [Location] = [location]
        var guardCount = 0
        while let next = stack.popLast(), guardCount < 100_000 {
            guardCount += 1
            for label in next.labelArray {
                label.location = nil
                label.targetType = .unassigned
            }
            stack.append(contentsOf: next.childArray)
        }
        context.delete(location)
    }

    private func isInside(_ location: Location?, _ container: Location) -> Bool {
        var current = location
        var guardCount = 0
        while let c = current, guardCount < 4096 {
            if c.objectID == container.objectID { return true }
            current = c.parent
            guardCount += 1
        }
        return false
    }

    private func sameProject(_ a: Location, _ b: Location) -> Bool {
        guard let pa = a.project, let pb = b.project else { return a.project === b.project }
        return pa.objectID == pb.objectID
    }
}
