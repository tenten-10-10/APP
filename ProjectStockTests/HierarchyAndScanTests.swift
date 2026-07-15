import XCTest
import CoreData
@testable import ProjectStock

final class HierarchyAndScanTests: XCTestCase {

    func testFolderCycleDetection() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let a = Folder.make(in: ctx, name: "A", project: project)
        let b = Folder.make(in: ctx, name: "B", project: project)
        try container.folders.setParent(b, to: a)   // B under A
        try ctx.save()

        XCTAssertThrowsError(try container.folders.setParent(a, to: b), "AをBの下に置くと循環") { error in
            guard case HierarchyError.wouldCreateCycle = error else { return XCTFail("循環検出すべき") }
        }
    }

    func testLocationCycleDetection() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let shelf = Location.make(in: ctx, name: "棚", project: project, kind: .shelf)
        let bin = Location.make(in: ctx, name: "箱", project: project, kind: .bin)
        try container.locations.setParent(bin, to: shelf)
        try ctx.save()

        XCTAssertThrowsError(try container.locations.setParent(shelf, to: bin)) { error in
            guard case HierarchyError.wouldCreateCycle = error else { return XCTFail("循環検出すべき") }
        }
    }

    func testBulkMoveContainerContents() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let boxA = Location.make(in: ctx, name: "箱A", project: project, kind: .container)
        let boxB = Location.make(in: ctx, name: "箱B", project: project, kind: .container)
        let product = Product.make(in: ctx, name: "部品", project: project)
        product.defaultLocation = boxA
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        container.inventory.setInitialStock(product: product, quantity: 5, location: boxA, actor: "t", in: ctx)
        try ctx.save()

        let moved = try container.locations.bulkMoveContents(of: boxA, to: boxB, actor: "t", in: ctx)
        try ctx.save()
        XCTAssertEqual(moved.products, 1)
        XCTAssertEqual(product.defaultLocation?.objectID, boxB.objectID, "一括移動で場所が更新される")
    }

    // MARK: - Scan routing (spec §8)

    func testScanRoutingClassifications() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let product = Product.make(in: ctx, name: "X", project: project)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)

        // Unassigned
        let unassigned = try container.aliases.createUnassignedBatch(count: 1, in: project, context: ctx).first!
        try ctx.save()
        if case .unassigned = container.scanRouter.route(rawValue: unassigned.code, in: ctx) {} else {
            XCTFail("未割当として分類されるべき")
        }

        // Known
        try container.aliases.assign(alias: unassigned, to: .product(product))
        try ctx.save()
        if case .known = container.scanRouter.route(rawValue: unassigned.code, in: ctx) {} else {
            XCTFail("既知として分類されるべき")
        }

        // Known via Universal Link URL (new label / deep-link form)
        let linkURL = "https://t.l0l0.app/\(unassigned.code)"
        if case .known = container.scanRouter.route(rawValue: linkURL, in: ctx) {} else {
            XCTFail("Universal LinkのURLからもコードを解決すべき")
        }

        // Retired
        container.aliases.retire(alias: unassigned)
        try ctx.save()
        if case .retired = container.scanRouter.route(rawValue: unassigned.code, in: ctx) {} else {
            XCTFail("無効として分類されるべき")
        }

        // Foreign
        if case .foreign = container.scanRouter.route(rawValue: "https://example.com", in: ctx) {} else {
            XCTFail("対象外として分類されるべき")
        }

        // App-format but unknown
        if case .unknownAppCode = container.scanRouter.route(rawValue: "IQZZZZZZZZZZZZZZZZ", in: ctx) {} else {
            XCTFail("未知のアプリコードとして分類されるべき")
        }
    }

    func testScanabilityWarnsOnTinyModules() throws {
        let encoder = CoreImageQREncoder()
        let matrix = try encoder.encode("IQ0123456789ABCDEF", errorCorrection: .high)
        // 6mm with high ECC -> tiny modules -> not recommended.
        let spec = QRRenderSpec(code: "IQ0123456789ABCDEF", totalSizeMM: 6, errorCorrection: .high, dpi: 300)
        let report = QRScanabilityEvaluator().evaluate(matrix: matrix, spec: spec)
        XCTAssertNotEqual(report.rating, .recommended, "極小サイズは推奨にならない")
        XCTAssertFalse(report.warnings.isEmpty)
    }
}
