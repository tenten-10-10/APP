import XCTest
import CoreData
@testable import ProjectStock

final class InventoryServiceTests: XCTestCase {

    func testLedgerTotalSumsDeltas() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let product = Product.make(in: ctx, name: "ネジ", project: project)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)

        container.inventory.setInitialStock(product: product, quantity: 100, location: nil, actor: "t", in: ctx)
        container.inventory.receive(product: product, quantity: 20, location: nil, actor: "t", in: ctx)
        container.inventory.consume(product: product, quantity: 30, location: nil, actor: "t", in: ctx)
        try ctx.save()

        XCTAssertEqual(container.inventory.ledgerQuantity(for: product), 90, accuracy: 0.0001)
        XCTAssertEqual(product.cachedQuantity, 90, accuracy: 0.0001)
    }

    func testTransferDoesNotChangeTotal() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let product = Product.make(in: ctx, name: "部品", project: project)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        let locA = Location.make(in: ctx, name: "A", project: project)
        let locB = Location.make(in: ctx, name: "B", project: project)

        container.inventory.setInitialStock(product: product, quantity: 50, location: locA, actor: "t", in: ctx)
        container.inventory.transferQuantity(product: product, quantity: 50, from: locA, to: locB, actor: "t", in: ctx)
        try ctx.save()

        XCTAssertEqual(container.inventory.ledgerQuantity(for: product), 50, accuracy: 0.0001)
    }

    func testCorrectionReversesEvent() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let product = Product.make(in: ctx, name: "テープ", project: project)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)

        container.inventory.setInitialStock(product: product, quantity: 10, location: nil, actor: "t", in: ctx)
        let badReceive = container.inventory.receive(product: product, quantity: 99, location: nil, actor: "t", in: ctx)
        try ctx.save()
        XCTAssertEqual(product.cachedQuantity, 109, accuracy: 0.0001)

        let correction = container.inventory.reverse(event: badReceive, actor: "t", note: "誤入力", in: ctx)
        try ctx.save()
        XCTAssertTrue(correction.isCorrection)
        XCTAssertEqual(correction.correctsEvent?.objectID, badReceive.objectID)
        XCTAssertEqual(product.cachedQuantity, 10, accuracy: 0.0001, "訂正後は元の値へ戻る")
    }

    func testCachedQuantityRebuild() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let product = Product.make(in: ctx, name: "塗料", project: project)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        container.inventory.receive(product: product, quantity: 42, location: nil, actor: "t", in: ctx)
        try ctx.save()

        // Corrupt the cache then rebuild from the ledger.
        product.cachedQuantity = -999
        container.inventory.recompute(product: product)
        XCTAssertEqual(product.cachedQuantity, 42, accuracy: 0.0001, "台帳から再構築できる")
    }

    func testCorrectingTransferDoesNotChangeTotal() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let product = Product.make(in: ctx, name: "部品", project: project)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        let locA = Location.make(in: ctx, name: "A", project: project)
        let locB = Location.make(in: ctx, name: "B", project: project)

        container.inventory.setInitialStock(product: product, quantity: 10, location: locA, actor: "t", in: ctx)
        let move = container.inventory.transferQuantity(product: product, quantity: 10, from: locA, to: locB, actor: "t", in: ctx)
        try ctx.save()
        XCTAssertEqual(product.cachedQuantity, 10, accuracy: 0.0001)

        // Correcting a transfer must not change on-hand total (it never moved stock).
        container.inventory.reverse(event: move, actor: "t", note: "誤移動", in: ctx)
        try ctx.save()
        XCTAssertEqual(container.inventory.ledgerQuantity(for: product), 10, accuracy: 0.0001)
        XCTAssertEqual(product.cachedQuantity, 10, accuracy: 0.0001)
    }

    func testCorrectingCheckoutRestoresUnit() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let product = Product.make(in: ctx, name: "工具", project: project, trackingMode: .individual)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        let unit = StockUnit.make(in: ctx, serialNumber: "S1", product: product, project: project)
        container.router.assignChild(unit, toSameStoreAs: project, in: ctx)
        container.inventory.registerUnit(unit, location: nil, actor: "t", in: ctx)
        let checkout = container.inventory.checkout(unit: unit, actor: "t", in: ctx)
        try ctx.save()
        XCTAssertEqual(unit.status, .checkedOut)
        XCTAssertEqual(product.currentQuantity, 0, accuracy: 0.0001)

        // Correcting the checkout must actually undo it.
        container.inventory.reverse(event: checkout, actor: "t", note: "誤貸出", in: ctx)
        try ctx.save()
        XCTAssertEqual(unit.status, .available, "訂正で個体の状態が戻る")
        XCTAssertEqual(product.currentQuantity, 1, accuracy: 0.0001)
    }

    func testLoanTracksBorrowerDueDateAndOverdue() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let product = Product.make(in: ctx, name: "測定器", project: project, trackingMode: .individual)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        let unit = StockUnit.make(in: ctx, serialNumber: "M-01", product: product, project: project)
        container.router.assignChild(unit, toSameStoreAs: project, in: ctx)
        container.inventory.registerUnit(unit, location: nil, actor: "t", in: ctx)

        let past = Date(timeIntervalSinceNow: -3600)
        container.inventory.checkout(unit: unit, actor: "貸出担当", borrower: "佐藤", dueAt: past, in: ctx)
        try ctx.save()

        let loan = try XCTUnwrap(container.inventory.currentLoan(for: unit))
        XCTAssertEqual(loan.borrower, "佐藤")
        XCTAssertEqual(loan.dueAt?.timeIntervalSinceReferenceDate ?? 0,
                       past.timeIntervalSinceReferenceDate, accuracy: 0.001)
        XCTAssertTrue(loan.isOverdue, "期限を過ぎた貸出は overdue")
        XCTAssertEqual(container.inventory.activeLoans(in: ctx).count, 1)
        XCTAssertNotNil(loan.notice, "期限付き貸出は通知スナップショットを生成する")

        container.inventory.returnUnit(unit, to: nil, actor: "t", in: ctx)
        try ctx.save()
        XCTAssertNil(container.inventory.currentLoan(for: unit), "返却後は貸出なし")
        XCTAssertTrue(container.inventory.activeLoans(in: ctx).isEmpty)
    }

    func testIndividualUnitStatusFlow() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let product = Product.make(in: ctx, name: "工具", project: project, trackingMode: .individual)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        let unit = StockUnit.make(in: ctx, serialNumber: "S1", product: product, project: project)
        container.router.assignChild(unit, toSameStoreAs: project, in: ctx)
        container.inventory.registerUnit(unit, location: nil, actor: "t", in: ctx)
        XCTAssertEqual(product.currentQuantity, 1, accuracy: 0.0001)

        container.inventory.checkout(unit: unit, actor: "t", in: ctx)
        XCTAssertEqual(unit.status, .checkedOut)
        XCTAssertEqual(product.currentQuantity, 0, accuracy: 0.0001, "貸出中は在庫から外れる")

        container.inventory.returnUnit(unit, to: nil, actor: "t", in: ctx)
        XCTAssertEqual(unit.status, .available)
        XCTAssertEqual(product.currentQuantity, 1, accuracy: 0.0001)
    }
}
