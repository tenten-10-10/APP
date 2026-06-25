import Foundation
import CoreData

/// Manages QR labels (`CodeAlias`): pre-printing unassigned codes, lookups,
/// assignment, and retirement. Uniqueness is enforced in the app layer (spec
/// §6) — there are no CloudKit unique constraints.
struct CodeAliasService {

    let generator: PublicCodeGenerator
    let router: StoreRouter

    init(generator: PublicCodeGenerator = PublicCodeGenerator(), router: StoreRouter) {
        self.generator = generator
        self.router = router
    }

    // MARK: - Lookup

    /// Find the alias for a scanned code anywhere in the local stores.
    func findAlias(forCode code: String, in context: NSManagedObjectContext) -> CodeAlias? {
        let request: NSFetchRequest<CodeAlias> = CodeAlias.fetchRequest()
        request.predicate = NSPredicate(format: "publicCode == %@", code)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Whether a code already exists locally.
    func codeExists(_ code: String, in context: NSManagedObjectContext) -> Bool {
        let request: NSFetchRequest<CodeAlias> = CodeAlias.fetchRequest()
        request.predicate = NSPredicate(format: "publicCode == %@", code)
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
    }

    // MARK: - Pre-printing unassigned codes (spec §4.2)

    /// Create `count` fresh, mutually-unique unassigned aliases in a project.
    @discardableResult
    func createUnassignedBatch(count: Int, in project: Project,
                               context: NSManagedObjectContext) throws -> [CodeAlias] {
        let codes = try generator.generateUniqueBatch(count: count) { candidate in
            codeExists(candidate, in: context)
        }
        return codes.map { code in
            let alias = CodeAlias.make(in: context, publicCode: code, project: project)
            router.assignChild(alias, toSameStoreAs: project, in: context)
            return alias
        }
    }

    /// Create a single alias already bound to a target (used when minting a
    /// label directly for an existing product/unit/location).
    @discardableResult
    func createAlias(for target: AliasTarget, in project: Project,
                     context: NSManagedObjectContext) throws -> CodeAlias {
        let code = try generator.generateUnique { codeExists($0, in: context) }
        let alias = CodeAlias.make(in: context, publicCode: code, project: project)
        router.assignChild(alias, toSameStoreAs: project, in: context)
        try assign(alias: alias, to: target)
        return alias
    }

    // MARK: - Assignment (spec §4.2)

    enum AliasTarget {
        case product(Product)
        case unit(StockUnit)
        case location(Location)
    }

    /// Bind an unassigned (or reassignable active) alias to a target in the
    /// SAME project. Retired aliases must never be reassigned (spec §6).
    func assign(alias: CodeAlias, to target: AliasTarget) throws {
        guard alias.isActive else { throw AppError.invalidHierarchy(NSLocalizedString("無効化されたラベルは再割当できません。", comment: "")) }

        switch target {
        case .product(let product):
            try requireSameProject(alias, product.project)
            alias.product = product
            alias.unit = nil
            alias.location = nil
            alias.targetType = .product
        case .unit(let unit):
            try requireSameProject(alias, unit.project)
            alias.unit = unit
            alias.product = nil
            alias.location = nil
            alias.targetType = .unit
        case .location(let location):
            try requireSameProject(alias, location.project)
            alias.location = location
            alias.product = nil
            alias.unit = nil
            alias.targetType = .location
        }
    }

    // MARK: - Retirement (spec §4.2: history is never deleted)

    func retire(alias: CodeAlias) {
        alias.isActive = false
        alias.retiredAt = Date()
        // The historical target links are intentionally preserved.
    }

    func registerScan(alias: CodeAlias, at date: Date = Date()) {
        alias.registerScan(at: date)
    }

    // MARK: - Helpers

    private func requireSameProject(_ alias: CodeAlias, _ targetProject: Project?) throws {
        guard let aliasProject = alias.project, let targetProject else {
            throw AppError.crossProjectReference
        }
        guard aliasProject.objectID == targetProject.objectID else {
            throw AppError.crossProjectReference
        }
    }
}
