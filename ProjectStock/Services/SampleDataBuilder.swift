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
        // Check one out for the demo, overdue, so the loans screen has content.
        if let firstUnit = driver.unitArray.first {
            let due = Calendar.current.date(byAdding: .day, value: -2, to: Date())
            inventory.checkout(unit: firstUnit, actor: project.ownerDisplayName ?? "",
                               borrower: NSLocalizedString("田中", comment: ""), dueAt: due,
                               note: NSLocalizedString("現場へ持ち出し", comment: ""), in: context)
        }

        // Lot-tracked product: two lots, one near expiry and one already expired.
        let glue = makeProduct(NSLocalizedString("接着剤", comment: ""), sku: "GLUE-A",
                               unit: NSLocalizedString("本", comment: ""), folder: parts,
                               location: binB, in: project, context: context)
        glue.trackingMode = .lot
        let soon = Calendar.current.date(byAdding: .day, value: 20, to: Date())
        let expired = Calendar.current.date(byAdding: .day, value: -5, to: Date())
        _ = inventory.createLot(product: glue, lotNumber: "LOT-2406", quantity: 12, expiresAt: soon,
                                location: binB, actor: project.ownerDisplayName ?? "", in: context)
        if let oldLot = inventory.createLot(product: glue, lotNumber: "LOT-2312", quantity: 5, expiresAt: expired,
                                            location: binB, actor: project.ownerDisplayName ?? "", in: context) {
            _ = try? aliases.createAlias(for: .unit(oldLot), in: project, context: context)
        }

        // Labels: a couple of pre-printed unassigned codes + bound ones.
        _ = try? aliases.createUnassignedBatch(count: 3, in: project, context: context)
        _ = try? aliases.createAlias(for: .product(screw), in: project, context: context)
        _ = try? aliases.createAlias(for: .location(binA), in: project, context: context)

        inventory.recomputeAll(in: project)
        return project
    }

    // MARK: - Showcase (App Store screenshots, three industries)

    /// Builds three industry demo projects so screenshots show the app in
    /// realistic, varied use (sales samples / factory parts / café lots).
    @discardableResult
    func makeShowcaseProjects(in context: NSManagedObjectContext,
                              owner: String = NSLocalizedString("デモ担当", comment: "")) throws -> [Project] {
        let sales = try makeSalesSamples(owner: owner, in: context)
        let factory = makeFactory(owner: owner, in: context)
        let cafe = makeCafe(owner: owner, in: context)
        return [sales, factory, cafe]
    }

    private func days(_ n: Int) -> Date? {
        Calendar.current.date(byAdding: .day, value: n, to: Date())
    }

    /// 営業サンプル（建材/内装の商社）— 個体管理＋貸出が主役。
    private func makeSalesSamples(owner: String, in ctx: NSManagedObjectContext) throws -> Project {
        let p = projects.createProject(name: NSLocalizedString("サンプル営業部", comment: ""),
                                       ownerDisplayName: owner, color: .olive, isSample: true,
                                       defaultMode: .individual, in: ctx)
        p.note = NSLocalizedString("得意先へ貸し出す営業サンプルを、1点ずつQRで管理。", comment: "")
        let showroom = makeLocation(NSLocalizedString("ショールーム", comment: ""), .room, in: p, context: ctx)
        let rack = makeLocation(NSLocalizedString("サンプル棚", comment: ""), .shelf, in: p, context: ctx)
        let cat = makeFolder(NSLocalizedString("内装材", comment: ""), in: p, context: ctx)

        func sample(_ name: String, sku: String, serials: [String], lentTo: String?) {
            let prod = makeProduct(name, sku: sku, unit: NSLocalizedString("点", comment: ""),
                                   folder: cat, location: rack, in: p, context: ctx)
            prod.trackingMode = .individual
            for s in serials {
                let u = StockUnit.make(in: ctx, serialNumber: s, product: prod, project: p, location: rack)
                router.assignChild(u, toSameStoreAs: p, in: ctx)
                inventory.registerUnit(u, location: rack, actor: owner, in: ctx)
                _ = try? aliases.createAlias(for: .unit(u), in: p, context: ctx)
            }
            if let borrower = lentTo, let u = prod.unitArray.first {
                inventory.checkout(unit: u, actor: owner, borrower: borrower, dueAt: days(5),
                                   note: NSLocalizedString("商談用に貸出", comment: ""), in: ctx)
            }
        }
        sample(NSLocalizedString("フローリング オーク", comment: ""), sku: "FL-OAK",
               serials: ["OAK-01", "OAK-02", "OAK-03"], lentTo: NSLocalizedString("山田建設", comment: ""))
        sample(NSLocalizedString("タイル 300角 グレー", comment: ""), sku: "TL-300",
               serials: ["TL-01", "TL-02"], lentTo: NSLocalizedString("鈴木設計", comment: ""))
        sample(NSLocalizedString("木目調パネル ウォルナット", comment: ""), sku: "PN-WAL",
               serials: ["WAL-01", "WAL-02", "WAL-03", "WAL-04"], lentTo: nil)
        _ = try? aliases.createUnassignedBatch(count: 4, in: p, context: ctx)
        showroom.touch()
        inventory.recomputeAll(in: p)
        return p
    }

    /// 製造・整備（工場）— 数量在庫＋工具貸出、低在庫バッジ。
    private func makeFactory(owner: String, in ctx: NSManagedObjectContext) -> Project {
        let p = projects.createProject(name: NSLocalizedString("第一工場 整備課", comment: ""),
                                       ownerDisplayName: owner, color: .teal, isSample: true, in: ctx)
        p.note = NSLocalizedString("部品在庫と工具の貸出をQRで管理。", comment: "")
        let wh = makeLocation(NSLocalizedString("資材倉庫", comment: ""), .site, in: p, context: ctx)
        let rack = makeLocation(NSLocalizedString("ラックB", comment: ""), .shelf, parent: wh, in: p, context: ctx)
        let parts = makeFolder(NSLocalizedString("部品", comment: ""), in: p, context: ctx)
        let tools = makeFolder(NSLocalizedString("工具", comment: ""), in: p, context: ctx)

        let bolt = makeProduct(NSLocalizedString("M4 ボルト", comment: ""), sku: "BLT-M4",
                               unit: NSLocalizedString("本", comment: ""), folder: parts, location: rack, in: p, context: ctx)
        bolt.minimumStock = 200
        inventory.setInitialStock(product: bolt, quantity: 1500, location: rack, actor: owner, in: ctx)
        inventory.consume(product: bolt, quantity: 320, location: rack, actor: owner,
                          note: NSLocalizedString("ライン補充", comment: ""), in: ctx)

        let bearing = makeProduct(NSLocalizedString("ベアリング 6203", comment: ""), sku: "BRG-6203",
                                  unit: NSLocalizedString("個", comment: ""), folder: parts, location: rack, in: p, context: ctx)
        bearing.minimumStock = 50
        inventory.setInitialStock(product: bearing, quantity: 38, location: rack, actor: owner, in: ctx)

        let oil = makeProduct(NSLocalizedString("潤滑油 1L", comment: ""), sku: "OIL-1L",
                              unit: NSLocalizedString("缶", comment: ""), folder: parts, location: wh, in: p, context: ctx)
        inventory.setInitialStock(product: oil, quantity: 24, location: wh, actor: owner, in: ctx)

        let wrench = makeProduct(NSLocalizedString("トルクレンチ", comment: ""), sku: "TQ-W",
                                 unit: NSLocalizedString("本", comment: ""), folder: tools, location: wh, in: p, context: ctx)
        wrench.trackingMode = .individual
        for i in 1...2 {
            let u = StockUnit.make(in: ctx, serialNumber: String(format: "TQ-%02d", i), product: wrench, project: p, location: wh)
            router.assignChild(u, toSameStoreAs: p, in: ctx)
            inventory.registerUnit(u, location: wh, actor: owner, in: ctx)
            _ = try? aliases.createAlias(for: .unit(u), in: p, context: ctx)
        }
        if let u = wrench.unitArray.first {
            inventory.checkout(unit: u, actor: owner, borrower: NSLocalizedString("佐藤", comment: ""),
                               dueAt: days(-1), note: NSLocalizedString("ライン保全", comment: ""), in: ctx)
        }
        _ = try? aliases.createAlias(for: .product(bolt), in: p, context: ctx)
        inventory.recomputeAll(in: p)
        return p
    }

    /// 飲食/カフェ — ロット＋賞味期限が主役（期限切れ/間近のバッジ）。
    private func makeCafe(owner: String, in ctx: NSManagedObjectContext) -> Project {
        let p = projects.createProject(name: NSLocalizedString("カフェ・ハル 在庫", comment: ""),
                                       ownerDisplayName: owner, color: .orange, isSample: true,
                                       defaultMode: .lot, in: ctx)
        p.note = NSLocalizedString("食材をロット・賞味期限つきで管理。期限切れはバッジで警告。", comment: "")
        let store = makeLocation(NSLocalizedString("食材庫", comment: ""), .room, in: p, context: ctx)
        let fridge = makeLocation(NSLocalizedString("冷蔵庫", comment: ""), .container, parent: store, in: p, context: ctx)
        let ing = makeFolder(NSLocalizedString("食材", comment: ""), in: p, context: ctx)

        let beans = makeProduct(NSLocalizedString("コーヒー豆 ブレンド", comment: ""), sku: "BEAN-BL",
                                unit: "kg", folder: ing, location: store, in: p, context: ctx)
        beans.trackingMode = .lot
        _ = inventory.createLot(product: beans, lotNumber: "RST-2406", quantity: 8, expiresAt: days(25), location: store, actor: owner, in: ctx)
        _ = inventory.createLot(product: beans, lotNumber: "RST-2405", quantity: 3, expiresAt: days(-3), location: store, actor: owner, in: ctx)

        let syrup = makeProduct(NSLocalizedString("バニラシロップ", comment: ""), sku: "SYR-VAN",
                                unit: NSLocalizedString("本", comment: ""), folder: ing, location: fridge, in: p, context: ctx)
        syrup.trackingMode = .lot
        _ = inventory.createLot(product: syrup, lotNumber: "VS-118", quantity: 6, expiresAt: days(10), location: fridge, actor: owner, in: ctx)

        let milk = makeProduct(NSLocalizedString("牛乳 1L", comment: ""), sku: "MILK-1L",
                               unit: NSLocalizedString("本", comment: ""), folder: ing, location: fridge, in: p, context: ctx)
        milk.trackingMode = .lot
        _ = inventory.createLot(product: milk, lotNumber: "MK-0626", quantity: 12, expiresAt: days(4), location: fridge, actor: owner, in: ctx)

        let cup = makeProduct(NSLocalizedString("紙カップ M", comment: ""), sku: "CUP-M",
                              unit: NSLocalizedString("個", comment: ""), folder: ing, location: store, in: p, context: ctx)
        cup.minimumStock = 200
        inventory.setInitialStock(product: cup, quantity: 150, location: store, actor: owner, in: ctx)

        _ = try? aliases.createAlias(for: .product(beans), in: p, context: ctx)
        inventory.recomputeAll(in: p)
        return p
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
