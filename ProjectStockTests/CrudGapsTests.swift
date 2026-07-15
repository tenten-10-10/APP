import XCTest
import CoreData
@testable import ProjectStock

/// 1.2.51: 「変えられない・消せない」の解消（リネーム・貸出編集・QR解除・
/// 場所/フォルダ削除・棚卸し補正）のテスト。
final class CrudGapsTests: XCTestCase {

    func testRenameUnitAndLotKeepsIdentity() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let product = Product.make(in: ctx, name: "デモ機", project: project, trackingMode: .individual)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        let unit = StockUnit.make(in: ctx, serialNumber: "#1", product: product, project: project)
        container.router.assignChild(unit, toSameStoreAs: project, in: ctx)
        container.inventory.registerUnit(unit, location: nil, actor: "t", in: ctx)
        let lot = StockUnit.makeLot(in: ctx, lotNumber: "L-001", product: product, project: project)
        container.router.assignChild(lot, toSameStoreAs: project, in: ctx)
        try ctx.save()

        container.inventory.renameUnit(unit, to: "展示用サンプル 003")
        container.inventory.renameUnit(lot, to: "L-002")
        try ctx.save()

        XCTAssertEqual(unit.displaySerial, "展示用サンプル 003")
        XCTAssertEqual(lot.lotNumberDisplay, "L-002")
        XCTAssertEqual(unit.status, .available, "リネームで状態は変わらない")
        XCTAssertFalse(unit.eventArray.isEmpty, "登録イベントはそのまま残る")
    }

    func testUpdateLoanEditsBorrowerAndDueWithoutResettingSince() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let product = Product.make(in: ctx, name: "測定器", project: project, trackingMode: .individual)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        let unit = StockUnit.make(in: ctx, serialNumber: "M-01", product: product, project: project)
        container.router.assignChild(unit, toSameStoreAs: project, in: ctx)
        container.inventory.registerUnit(unit, location: nil, actor: "t", in: ctx)
        container.inventory.checkout(unit: unit, actor: "t", borrower: "山口", dueAt: nil, in: ctx)
        try ctx.save()

        let before = try XCTUnwrap(container.inventory.currentLoan(for: unit))
        XCTAssertNil(before.dueAt, "期限なしで貸出")

        let newDue = Date(timeIntervalSinceNow: 7 * 24 * 3600)
        XCTAssertTrue(container.inventory.updateLoan(for: unit, borrower: "山田", dueAt: newDue))
        try ctx.save()

        let after = try XCTUnwrap(container.inventory.currentLoan(for: unit))
        XCTAssertEqual(after.borrower, "山田", "借り手名を修正できる")
        XCTAssertEqual(after.dueAt?.timeIntervalSinceReferenceDate ?? 0,
                       newDue.timeIntervalSinceReferenceDate, accuracy: 0.001,
                       "期限を後から設定できる")
        XCTAssertEqual(after.since.timeIntervalSinceReferenceDate,
                       before.since.timeIntervalSinceReferenceDate, accuracy: 0.001,
                       "貸出日はリセットされない")

        // 貸出中でない個体には効かない
        container.inventory.returnUnit(unit, to: nil, actor: "t", in: ctx)
        XCTAssertFalse(container.inventory.updateLoan(for: unit, borrower: "誰か", dueAt: nil))
    }

    func testUnassignReturnsLabelToBlankAndReusable() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let productA = Product.make(in: ctx, name: "A", project: project)
        let productB = Product.make(in: ctx, name: "B", project: project)
        container.router.assignChild(productA, toSameStoreAs: project, in: ctx)
        container.router.assignChild(productB, toSameStoreAs: project, in: ctx)
        let alias = try container.aliases.createAlias(for: .product(productA), in: project, context: ctx)
        try ctx.save()

        container.aliases.unassign(alias: alias)
        XCTAssertEqual(alias.targetType, .unassigned)
        XCTAssertNil(alias.product)
        XCTAssertTrue(alias.isActive, "解除は無効化ではない")

        // 同じ印刷済みQRを別の製品に割り当て直せる
        try container.aliases.assign(alias: alias, to: .product(productB))
        XCTAssertEqual(alias.product?.objectID, productB.objectID)
    }

    func testDeleteLocationKeepsInventoryAndFreesLabels() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let warehouse = Location.make(in: ctx, name: "倉庫A", project: project, kind: .site)
        container.router.assignChild(warehouse, toSameStoreAs: project, in: ctx)
        let shelf = Location.make(in: ctx, name: "棚3", project: project, kind: .shelf)
        container.router.assignChild(shelf, toSameStoreAs: project, in: ctx)
        try container.locations.setParent(shelf, to: warehouse)

        let product = Product.make(in: ctx, name: "ネジ", project: project)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        product.defaultLocation = shelf
        container.inventory.setInitialStock(product: product, quantity: 10, location: shelf, actor: "t", in: ctx)

        let alias = try container.aliases.createAlias(for: .location(shelf), in: project, context: ctx)
        try ctx.save()

        container.locations.deleteLocation(warehouse, in: ctx)
        try ctx.save()

        let locReq: NSFetchRequest<Location> = Location.fetchRequest()
        XCTAssertEqual(try ctx.count(for: locReq), 0, "サブの場所ごと削除される")
        XCTAssertNil(product.defaultLocation, "製品は残り、場所だけ外れる")
        XCTAssertEqual(product.currentQuantity, 10, accuracy: 0.0001, "在庫数は失われない")
        XCTAssertNil(alias.location)
        XCTAssertEqual(alias.targetType, .unassigned, "場所のQRは空に戻る")
    }

    func testDeleteFolderKeepsProducts() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let folder = Folder.make(in: ctx, name: "部品", project: project)
        container.router.assignChild(folder, toSameStoreAs: project, in: ctx)
        let product = Product.make(in: ctx, name: "抵抗", project: project)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        product.folder = folder
        try ctx.save()

        ctx.delete(folder)
        try ctx.save()

        XCTAssertNil(product.folder, "フォルダなしに戻るだけ")
        XCTAssertFalse(product.isDeleted, "製品は消えない")
    }

    func testStocktakeRemoveLineFreesUnitCodes() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let product = Product.make(in: ctx, name: "工具", project: project, trackingMode: .individual)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        try ctx.save()

        let stocktake = StocktakeCoordinator(inventory: container.inventory)
        stocktake.begin(projectID: project.objectID)
        stocktake.record(product: product, unitCode: "TNM-0001")
        stocktake.record(product: product, unitCode: "TNM-0001")   // 二度読みは無視
        XCTAssertEqual(stocktake.lines.first?.counted ?? 0, 1, accuracy: 0.0001)

        stocktake.removeLine(for: product.objectID)
        XCTAssertTrue(stocktake.lines.isEmpty)

        // 取り除いた個体はもう一度カウントできる
        stocktake.record(product: product, unitCode: "TNM-0001")
        XCTAssertEqual(stocktake.lines.first?.counted ?? 0, 1, accuracy: 0.0001)
    }
}
