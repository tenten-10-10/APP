import Foundation
import CoreData

/// Builds a realistic demo project in one tap (spec §18, §12.2). Used for the
/// App Store reviewer flow and for first-run exploration.
struct SampleDataBuilder {

    let projects: ProjectService
    let inventory: InventoryService
    let aliases: CodeAliasService
    let router: StoreRouter

    init(projects: ProjectService, inventory: InventoryService,
         aliases: CodeAliasService, router: StoreRouter) {
        self.projects = projects
        self.inventory = inventory
        self.aliases = aliases
        self.router = router
    }

    /// Creates and returns a fully populated sample project. Caller saves.
    @discardableResult
    func makeSampleProject(in context: NSManagedObjectContext,
                           owner: String = NSLocalizedString("サンプル担当者", comment: "")) throws -> Project {
        let project = projects.createProject(name: NSLocalizedString("サンプル工房", comment: ""),
                                             ownerDisplayName: owner, color: .teal, isSample: true,
                                             in: context)
        project.note = NSLocalizedString("動作確認用のサンプルデータです。いつでも削除できます。", comment: "")

        // Locations
        let warehouse = makeLocation(NSLocalizedString("倉庫A", comment: ""), .site, in: project, context: context)
        let shelf = makeLocation(NSLocalizedString("棚3", comment: ""), .shelf, parent: warehouse, in: project, context: context)
        let binA = makeLocation(NSLocalizedString("箱A", comment: ""), .container, parent: shelf, in: project, context: context)
        let binB = makeLocation(NSLocalizedString("箱B", comment: ""), .container, parent: shelf, in: project, context: context)
        let bench = makeLocation(NSLocalizedString("作業台", comment: ""), .room, in: project, context: context)

        // Folders
        let parts = makeFolder(NSLocalizedString("部品", comment: ""), in: project, context: context)
        let tools = makeFolder(NSLocalizedString("工具", comment: ""), in: project, context: context)

        // Quantity-tracked products
        let screw = makeProduct(NSLocalizedString("M3ネジ", comment: ""), sku: "SCR-M3-10",
                                unit: NSLocalizedString("本", comment: ""), folder: parts,
                                location: binA, in: project, context: context)
        screw.minimumStock = 50
        inventory.setInitialStock(product: screw, quantity: 500, location: binA, actor: project.ownerDisplayName ?? "", in: context)
        inventory.consume(product: screw, quantity: 120, location: binA, actor: project.ownerDisplayName ?? "",
                          note: NSLocalizedString("試作で使用", comment: ""), in: context)

        let resistor = makeProduct(NSLocalizedString("抵抗 10kΩ", comment: ""), sku: "RES-10K",
                                   unit: NSLocalizedString("個", comment: ""), folder: parts,
                                   location: binB, in: project, context: context)
        resistor.minimumStock = 100
        inventory.setInitialStock(product: resistor, quantity: 80, location: binB, actor: project.ownerDisplayName ?? "", in: context)
        // 80 <= 100 -> intentionally low stock for the demo badge.

        let tape = makeProduct(NSLocalizedString("絶縁テープ", comment: ""), sku: "TAPE-BLK",
                               unit: NSLocalizedString("巻", comment: ""), folder: parts,
                               location: shelf, in: project, context: context)
        inventory.setInitialStock(product: tape, quantity: 24, location: shelf, actor: project.ownerDisplayName ?? "", in: context)

        // Individually-tracked product
        let driver = makeProduct(NSLocalizedString("電動ドライバー", comment: ""), sku: "TOOL-DRV",
                                 unit: NSLocalizedString("台", comment: ""), folder: tools,
                                 location: bench, in: project, context: context)
        driver.trackingMode = .individual
        for i in 1...3 {
            let unit = StockUnit.make(in: context, serialNumber: String(format: "DRV-%03d", i),
                                      product: driver, project: project, location: bench)
            router.assignChild(unit, toSameStoreAs: project, in: context)
            inventory.registerUnit(unit, location: bench, actor: project.ownerDisplayName ?? "", in: context)
        }
        // Check one out for the demo.
        if let firstUnit = driver.unitArray.first {
            inventory.checkout(unit: firstUnit, actor: project.ownerDisplayName ?? "",
                               note: NSLocalizedString("現場へ持ち出し", comment: ""), in: context)
        }

        // Labels: a couple of pre-printed unassigned codes + bound ones.
        _ = try? aliases.createUnassignedBatch(count: 3, in: project, context: context)
        _ = try? aliases.createAlias(for: .product(screw), in: project, context: context)
        _ = try? aliases.createAlias(for: .location(binA), in: project, context: context)

        inventory.recomputeAll(in: project)
        return project
    }

    // MARK: - Builders

    private func makeLocation(_ name: String, _ kind: LocationKind, parent: Location? = nil,
                              in project: Project, context: NSManagedObjectContext) -> Location {
        let location = Location.make(in: context, name: name, project: project, kind: kind, parent: parent)
        router.assignChild(location, toSameStoreAs: project, in: context)
        return location
    }

    private func makeFolder(_ name: String, in project: Project, context: NSManagedObjectContext) -> Folder {
        let folder = Folder.make(in: context, name: name, project: project)
        router.assignChild(folder, toSameStoreAs: project, in: context)
        return folder
    }

    private func makeProduct(_ name: String, sku: String, unit: String, folder: Folder?,
                             location: Location?, in project: Project, context: NSManagedObjectContext) -> Product {
        let product = Product.make(in: context, name: name, project: project, sku: sku,
                                   unitName: unit, folder: folder)
        product.defaultLocation = location
        router.assignChild(product, toSameStoreAs: project, in: context)
        return product
    }
}
