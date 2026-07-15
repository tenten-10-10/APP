import XCTest
import CoreData
@testable import ProjectStock

final class HandyBarcodeTests: XCTestCase {

    // MARK: - BarcodeCode validation

    func testNormalizeAcceptsValidJANAndITF() {
        XCTAssertEqual(BarcodeCode.normalize("4901234567894"), "4901234567894", "標準JAN(EAN-13)")
        XCTAssertEqual(BarcodeCode.normalize(" 4901234567894 \n"), "4901234567894", "前後の空白は除去")
        XCTAssertEqual(BarcodeCode.normalize("49123456"), "49123456", "短縮JAN(EAN-8)")
        XCTAssertEqual(BarcodeCode.normalize("14901234567891"), "14901234567891", "ITF-14（JANに梱包指示子1）")
    }

    func testNormalizeRejectsInvalid() {
        XCTAssertNil(BarcodeCode.normalize("4901234567890"), "チェックデジット不一致")
        XCTAssertNil(BarcodeCode.normalize("490123456789"), "12桁でもUPC-Aとしてチェック不一致なら拒否")
        XCTAssertNil(BarcodeCode.normalize("IQ0123456789ABCDEF"), "アプリQRコード形式は対象外")
        XCTAssertNil(BarcodeCode.normalize("https://t.l0l0.app/IQ0123456789ABCDEF"), "URLは対象外")
        XCTAssertNil(BarcodeCode.normalize(""), "空")
        XCTAssertNil(BarcodeCode.normalize("49012345678941"), "14桁だがチェック不一致")
        XCTAssertNil(BarcodeCode.normalize("4901２３4567894"), "全角数字混入は拒否")
    }

    func testCheckDigitMath() {
        XCTAssertTrue(BarcodeCode.hasValidCheckDigit("4901234567894"))
        XCTAssertFalse(BarcodeCode.hasValidCheckDigit("4901234567895"))
    }

    // MARK: - Barcode alias → product mapping (ハンディの解決経路)

    func testBarcodeAliasResolvesToProduct() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let product = Product.make(in: ctx, name: "ペルチェサンプル", project: project,
                                   sku: "4901234567894", trackingMode: .quantity)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)

        let alias = CodeAlias.make(in: ctx, publicCode: "4901234567894", project: project)
        container.router.assignChild(alias, toSameStoreAs: project, in: ctx)
        try container.aliases.assign(alias: alias, to: .product(product))
        try ctx.save()

        let found = container.aliases.findAlias(forCode: "4901234567894", in: ctx)
        XCTAssertNotNil(found, "数字コードでもfindAliasで見つかる")
        XCTAssertEqual(found?.targetType, .product)
        XCTAssertEqual(found?.product?.objectID, product.objectID)
        // 既存のQRルーティングは数字コードを .foreign として扱い続ける（無干渉）。
        if case .foreign = container.scanRouter.route(rawValue: "4901234567894", in: ctx) {} else {
            XCTFail("数字コードは既存ルータでは .foreign のまま（ハンディだけが解決する）")
        }
    }

    // MARK: - スキャン登録の個体モード（QRが個体にひも付く回帰テスト）

    func testIndividualAssignBindsAliasToUnitNotProduct() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        // NewProductAssignView.create() の個体モードと同じサービス呼び出し列。
        let product = Product.make(in: ctx, name: "デモ機", project: project, trackingMode: .individual)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        let unit = StockUnit.make(in: ctx, serialNumber: "#1", product: product, project: project, location: nil)
        container.router.assignChild(unit, toSameStoreAs: project, in: ctx)
        container.inventory.registerUnit(unit, location: nil, actor: "t", in: ctx)

        let alias = CodeAlias.make(in: ctx, publicCode: "IQTESTTESTTESTTE01", project: project)
        container.router.assignChild(alias, toSameStoreAs: project, in: ctx)
        try container.aliases.assign(alias: alias, to: .unit(unit))
        try ctx.save()

        XCTAssertEqual(alias.targetType, .unit, "QRは製品ではなく個体にひも付く")
        XCTAssertEqual(alias.unit?.objectID, unit.objectID)
        XCTAssertNil(alias.product)
        XCTAssertEqual(unit.status, .available)
        XCTAssertEqual(product.currentQuantity, 1, accuracy: 0.0001, "registerUnitで在庫+1")
    }
}
