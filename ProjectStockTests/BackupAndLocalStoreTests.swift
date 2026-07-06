import XCTest
import CoreData
@testable import ProjectStock

/// 1.2.11: 同期消失対策（バックアップ/復元）と、お試しデータのローカル
/// ストア分離のテスト。
final class BackupAndLocalStoreTests: XCTestCase {

    // MARK: - Store routing

    func testSampleProjectGoesToLocalStoreAndRealProjectToPrivate() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext

        let real = container.projects.createProject(name: "本番", ownerDisplayName: "t", in: ctx)
        let sample = container.projects.createProject(name: "お試し", ownerDisplayName: "t",
                                                      isSample: true, in: ctx)
        try ctx.save()

        XCTAssertFalse(container.persistence.isInLocalStore(real), "実プロジェクトはprivateストア")
        XCTAssertTrue(container.persistence.isInLocalStore(sample), "お試しはローカル（非同期）ストア")
    }

    func testSampleDataBuilderLandsInLocalStore() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = try container.sampleData.makeSampleProject(in: ctx)
        try ctx.save()
        XCTAssertTrue(container.persistence.isInLocalStore(project))
        // 子オブジェクトも同じストアに入る（クロスストア関係の防止）。
        for product in project.productArray {
            XCTAssertTrue(container.persistence.isInLocalStore(product), product.displayName)
        }
    }

    // MARK: - Backup / restore round-trip

    func testBackupRestoreRoundTripAfterDataLoss() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container, name: "展示会")

        // 数量管理の製品
        let catalog = Product.make(in: ctx, name: "カタログ", project: project,
                                   unitName: "部", trackingMode: .quantity)
        catalog.minimumStock = 50
        container.router.assignChild(catalog, toSameStoreAs: project, in: ctx)
        container.inventory.setInitialStock(product: catalog, quantity: 240, location: nil, actor: "t", in: ctx)

        // 個体管理の製品（貸出中1・QRラベル付き）
        let demo = Product.make(in: ctx, name: "デモ機", project: project, trackingMode: .individual)
        container.router.assignChild(demo, toSameStoreAs: project, in: ctx)
        let unit = StockUnit.make(in: ctx, serialNumber: "#1", product: demo, project: project)
        container.router.assignChild(unit, toSameStoreAs: project, in: ctx)
        container.inventory.registerUnit(unit, location: nil, actor: "t", in: ctx)
        let alias = try container.aliases.createAlias(for: .unit(unit), in: project, context: ctx)
        let code = alias.code
        container.inventory.checkout(unit: unit, actor: "t", borrower: "山田",
                                     dueAt: Date(timeIntervalSinceNow: 3600), in: ctx)
        try ctx.save()

        let document = try container.backups.snapshot(in: ctx)
        XCTAssertEqual(document.projects.count, 1)
        XCTAssertEqual(document.projects[0].products.count, 2)

        // 同期事故を再現: プロジェクトが丸ごと消える。
        ctx.delete(project)
        try ctx.save()

        let restored = try container.backups.restore(document, actor: "t", in: ctx)
        try ctx.save()
        XCTAssertEqual(restored.count, 1)
        let restoredProject = try XCTUnwrap(restored.first)
        XCTAssertTrue(restoredProject.displayName.contains("展示会"))

        let products = restoredProject.productArray
        XCTAssertEqual(products.count, 2)
        let restoredCatalog = try XCTUnwrap(products.first { $0.displayName == "カタログ" })
        XCTAssertEqual(restoredCatalog.currentQuantity, 240, accuracy: 0.0001, "在庫数が復元される")
        XCTAssertEqual(restoredCatalog.minimumStock, 50, accuracy: 0.0001)

        let restoredDemo = try XCTUnwrap(products.first { $0.displayName == "デモ機" })
        let restoredUnit = try XCTUnwrap(restoredDemo.unitArray.first)
        XCTAssertEqual(restoredUnit.status, .checkedOut, "貸出中の状態ごと復元")
        let loan = container.inventory.currentLoan(for: restoredUnit)
        XCTAssertEqual(loan?.borrower, "山田", "借り手も復元される")
        XCTAssertEqual(restoredUnit.activeLabels.first?.code, code,
                       "元のQRコード文字列で復元される（印刷済みラベルがそのまま使える）")
    }

    func testRestoreNeverStealsLivingQRCodes() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container, name: "倉庫")
        let product = Product.make(in: ctx, name: "工具", project: project, trackingMode: .individual)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        let unit = StockUnit.make(in: ctx, serialNumber: "S1", product: product, project: project)
        container.router.assignChild(unit, toSameStoreAs: project, in: ctx)
        container.inventory.registerUnit(unit, location: nil, actor: "t", in: ctx)
        let alias = try container.aliases.createAlias(for: .unit(unit), in: project, context: ctx)
        try ctx.save()

        let document = try container.backups.snapshot(in: ctx)
        // 元データを消さずに復元（=コピー扱い）→ QRは元の個体のまま。
        _ = try container.backups.restore(document, actor: "t", in: ctx)
        try ctx.save()

        XCTAssertEqual(alias.unit?.objectID, unit.objectID, "既存QRの割り当ては奪われない")
        let request: NSFetchRequest<CodeAlias> = CodeAlias.fetchRequest()
        request.predicate = NSPredicate(format: "publicCode == %@", alias.code)
        XCTAssertEqual(try ctx.count(for: request), 1, "同じコードが二重生成されない")
    }

    func testBackupFileWriteListAndDelete() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        _ = TestSupport.makeProject(container, name: "P")
        try ctx.save()

        let document = try container.backups.snapshot(in: ctx)
        let url = try container.backups.writeBackup(document)
        defer { container.backups.deleteBackup(at: url) }

        XCTAssertTrue(container.backups.listBackups().contains { $0.url == url })
        let loaded = try container.backups.loadDocument(from: url)
        XCTAssertEqual(loaded.v, BackupService.schemaVersion)
        XCTAssertEqual(loaded.projects.count, document.projects.count)

        container.backups.deleteBackup(at: url)
        XCTAssertFalse(container.backups.listBackups().contains { $0.url == url })
    }
}
