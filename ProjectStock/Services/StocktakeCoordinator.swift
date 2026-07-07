import Foundation
import CoreData
import Combine

/// A continuous stocktake (棚卸し) session (spec §11). Scans accumulate counts
/// per product; duplicate reads of the same unit label within the session are
/// ignored. On confirm, the difference between counted and expected is written
/// as `adjust` events. Sessions can be left open and resumed.
final class StocktakeCoordinator: ObservableObject {

    let inventory: InventoryService

    @Published private(set) var session: Session?

    init(inventory: InventoryService) {
        self.inventory = inventory
    }

    struct CountLine: Identifiable {
        let productID: NSManagedObjectID
        var productName: String
        var expected: Double
        var counted: Double
        var unitLabel: String
        /// Unit codes counted into THIS line, so removing the line can free
        /// them from the session-wide dedupe set (a mis-scanned unit must be
        /// countable again after its line is removed).
        var unitCodes: Set<String> = []
        var id: NSManagedObjectID { productID }
        var delta: Double { counted - expected }
    }

    struct Session {
        let projectID: NSManagedObjectID
        var startedAt: Date
        var lines: [NSManagedObjectID: CountLine] = [:]
        /// Unit-level codes already counted, to dedupe repeat scans.
        var seenUnitCodes: Set<String> = []
        var scanTotal: Int = 0
    }

    var isActive: Bool { session != nil }

    func begin(projectID: NSManagedObjectID) {
        session = Session(projectID: projectID, startedAt: Date())
    }

    func cancel() { session = nil }

    /// Record a scanned product. `unitCode` (if the scan resolved to an
    /// individual unit) dedupes repeats. `increment` is how many to add for
    /// quantity products (default 1).
    func record(product: Product, increment: Double = 1, unitCode: String? = nil) {
        guard var current = session else { return }
        if let code = unitCode {
            if current.seenUnitCodes.contains(code) {
                session = current   // duplicate: count nothing
                return
            }
            current.seenUnitCodes.insert(code)
        }
        current.scanTotal += 1

        let id = product.objectID
        if var line = current.lines[id] {
            line.counted += increment
            if let code = unitCode { line.unitCodes.insert(code) }
            current.lines[id] = line
        } else {
            var line = CountLine(productID: id,
                                 productName: product.displayName,
                                 expected: product.currentQuantity,
                                 counted: increment,
                                 unitLabel: product.unitLabel)
            if let code = unitCode { line.unitCodes.insert(code) }
            current.lines[id] = line
        }
        session = current
    }

    /// Manually set a counted value for a product line (UI editing).
    func setCount(_ value: Double, for productID: NSManagedObjectID) {
        guard var current = session, var line = current.lines[productID] else { return }
        line.counted = max(0, value)
        current.lines[productID] = line
        session = current
    }

    /// Drop a mis-scanned line entirely. Its unit codes leave the dedupe set
    /// so the right items can still be counted afterwards.
    func removeLine(for productID: NSManagedObjectID) {
        guard var current = session else { return }
        if let line = current.lines[productID] {
            current.seenUnitCodes.subtract(line.unitCodes)
        }
        current.lines.removeValue(forKey: productID)
        session = current
    }

    var lines: [CountLine] {
        (session?.lines.values).map { Array($0).sorted { $0.productName < $1.productName } } ?? []
    }

    var discrepancyCount: Int {
        lines.filter { abs($0.delta) > 0.0001 }.count
    }

    /// Apply the counted values as `adjust` events on a background context.
    @discardableResult
    func confirm(using persistence: PersistenceController, actor: String) -> Result<Int, Error> {
        guard let session else { return .success(0) }
        let context = persistence.newTaskContext(author: "stocktake")
        var applied = 0
        var outcome: Result<Int, Error> = .success(0)
        context.performAndWait {
            do {
                for line in session.lines.values {
                    guard let product = try? context.existingObject(with: line.productID) as? Product else { continue }
                    guard abs(line.delta) > 0.0001 else { continue }
                    inventory.adjust(product: product, toCountedQuantity: line.counted,
                                     location: product.defaultLocation, actor: actor,
                                     note: NSLocalizedString("棚卸し", comment: ""), in: context)
                    applied += 1
                }
                if context.hasChanges { try context.save() }
                outcome = .success(applied)
            } catch {
                context.rollback()
                outcome = .failure(error)
            }
        }
        if case .success = outcome { self.session = nil }
        return outcome
    }
}
