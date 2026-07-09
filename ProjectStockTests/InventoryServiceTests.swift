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

    /// 実機で起きた不具合の回帰テスト: 貸出が真夜中(0:00)、初期登録が同日昼
    /// (13:16)に記録されると、orderingKey では初期登録が「後」に来る。以前は
    /// resolvedStatus がそれを拾って個体を .available に巻き戻し、製品詳細の
    /// 個体一覧から貸出中の個体（と返却ボタン）が消えていた。台帳に開いた貸出
    /// がある限り、初期登録のタイムスタンプが後でも貸出中として解決されるべき。
    func testCheckoutBackdatedBeforeCreateStaysOnLoan() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let product = Product.make(in: ctx, name: "サンプル", project: project, trackingMode: .individual)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        let unit = StockUnit.make(in: ctx, serialNumber: "S4", product: product, project: project)
        container.router.assignChild(unit, toSameStoreAs: project, in: ctx)

        let midnight = Calendar.current.startOfDay(for: Date())
        let afternoon = midnight.addingTimeInterval(13 * 3600 + 16 * 60)
        // 貸出を先に（0:00）、初期登録を後に（13:16）記録する。registerUnit は
        // unit.status を .available に上書きするので、この時点でキャッシュ済み
        // status は貸出と食い違って .available になっている（＝実機の壊れた状態）。
        container.inventory.checkout(unit: unit, actor: "麦倉", borrower: "加藤", occurredAt: midnight, in: ctx)
        container.inventory.registerUnit(unit, location: nil, actor: "麦倉", occurredAt: afternoon, in: ctx)
        try ctx.save()

        XCTAssertNotNil(container.inventory.currentLoan(for: unit),
                        "0:00の貸出が13:16の初期登録に隠されてはいけない")
        XCTAssertEqual(container.inventory.resolvedStatus(for: unit), .checkedOut,
                       "初期登録のタイムスタンプが後でも、台帳に開いた貸出があれば貸出中に解決される")
        XCTAssertEqual(container.inventory.activeLoans(in: ctx).count, 1, "貸出一覧にも出る")

        // 再解決でキャッシュ済み status も貸出中に治る（自己修復）。
        container.inventory.applyResolvedStatus(to: unit)
        XCTAssertEqual(unit.status, .checkedOut, "applyResolvedStatus でキャッシュも貸出中へ")

        // 返却すれば台帳上も解決し、貸出が消える。
        container.inventory.returnUnit(unit, to: nil, actor: "麦倉", in: ctx)
        try ctx.save()
        XCTAssertNil(container.inventory.currentLoan(for: unit), "返却後は貸出なし")
        XCTAssertEqual(container.inventory.resolvedStatus(for: unit), .available)
    }

    func testLotQuantityIsSumOfLedgerPerLotAndProduct() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let product = Product.make(in: ctx, name: "接着剤", project: project, trackingMode: .lot)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)

        let lot = try XCTUnwrap(container.inventory.createLot(product: product, lotNumber: "L1",
                                                              quantity: 10, expiresAt: nil,
                                                              location: nil, actor: "t", in: ctx))
        try ctx.save()
        XCTAssertEqual(lot.lotQuantity, 10, accuracy: 0.0001)
        XCTAssertEqual(product.currentQuantity, 10, accuracy: 0.0001)

        container.inventory.consumeFromLot(lot, quantity: 3, actor: "t", in: ctx)
        try ctx.save()
        XCTAssertEqual(lot.lotQuantity, 7, accuracy: 0.0001)

        let lot2 = try XCTUnwrap(container.inventory.createLot(product: product, lotNumber: "L2",
                                                               quantity: 5, expiresAt: nil,
                                                               location: nil, actor: "t", in: ctx))
        try ctx.save()
        XCTAssertEqual(lot2.lotQuantity, 5, accuracy: 0.0001)
        XCTAssertEqual(product.currentQuantity, 12, accuracy: 0.0001, "製品合計は全ロットの合計")
        XCTAssertEqual(product.lotArray.count, 2)
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

    func testDeleteUnitReleasesLabelAndKeepsLedgerRecord() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let product = Product.make(in: ctx, name: "デモ機", project: project, trackingMode: .individual)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        let unit = StockUnit.make(in: ctx, serialNumber: "#1", product: product, project: project)
        container.router.assignChild(unit, toSameStoreAs: project, in: ctx)
        container.inventory.registerUnit(unit, location: nil, actor: "t", in: ctx)
        let alias = try container.aliases.createAlias(for: .unit(unit), in: project, context: ctx)
        try ctx.save()
        XCTAssertEqual(product.currentQuantity, 1, accuracy: 0.0001)

        container.inventory.deleteUnit(unit, actor: "t", in: ctx)
        try ctx.save()

        XCTAssertTrue(product.unitArray.isEmpty, "個体はリストから消える")
        XCTAssertEqual(product.currentQuantity, 0, accuracy: 0.0001)
        XCTAssertNil(alias.unit, "QRラベルの割り当ては解除される")
        XCTAssertEqual(alias.targetType, .unassigned, "空のQRとして再利用できる")
        XCTAssertTrue(alias.isActive, "ラベル自体は無効化しない")
        XCTAssertTrue(product.eventArray.contains { $0.eventType == .retire && ($0.note ?? "").contains("削除") },
                      "削除の記録が履歴に残る")
    }

    func testDeleteProductCascadesUnitsAndReleasesLabels() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = TestSupport.makeProject(container)
        let product = Product.make(in: ctx, name: "撤去する製品", project: project, trackingMode: .individual)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        let unit = StockUnit.make(in: ctx, serialNumber: "#1", product: product, project: project)
        container.router.assignChild(unit, toSameStoreAs: project, in: ctx)
        container.inventory.registerUnit(unit, location: nil, actor: "t", in: ctx)
        let alias = try container.aliases.createAlias(for: .unit(unit), in: project, context: ctx)
        try ctx.save()

        container.inventory.deleteProduct(product, actor: "t", in: ctx)
        try ctx.save()

        let productReq: NSFetchRequest<Product> = Product.fetchRequest()
        let unitReq: NSFetchRequest<StockUnit> = StockUnit.fetchRequest()
        XCTAssertEqual(try ctx.count(for: productReq), 0, "製品は削除される")
        XCTAssertEqual(try ctx.count(for: unitReq), 0, "個体もカスケードで削除される")
        XCTAssertNil(alias.unit, "QRラベルの割り当ては解除される")
        XCTAssertEqual(alias.targetType, .unassigned)
        XCTAssertTrue(project.eventArray.contains { $0.eventType == .retire && ($0.note ?? "").contains("削除") },
                      "プロジェクトの履歴に削除の記録が残る")
    }

    // MARK: - Web借用フォームの日付解釈（0:00で記録しないための回帰テスト）

    private func webRequest(from: String?, until: String?,
                            createdAt: String = "2026-07-09T13:16:30Z") -> WebBorrowRequest {
        WebBorrowRequest(id: "r1", code: "ABC123", borrowerName: "佐藤",
                         borrowFrom: from, borrowUntil: until, destination: nil,
                         note: nil, status: "pending", createdAt: createdAt)
    }

    /// 借用開始日は「日付だけ」でも 0:00 にせず、申請時刻(created_at)の
    /// 時分秒を引き継ぐ（0:00だと同日の初期登録より前に並び、貸出中の個体が
    /// 一覧から消えるため）。日は borrow_from の日と一致する。
    func testWebBorrowStartDateCarriesApplicationTimeNotMidnight() {
        let req = webRequest(from: "2026-07-09", until: nil)
        let cal = Calendar.current
        XCTAssertEqual(cal.dateComponents([.hour, .minute, .second], from: req.startDate),
                       cal.dateComponents([.hour, .minute, .second], from: req.appliedAt),
                       "貸出開始の時刻は申請時刻を引き継ぐ")
        let expectedDay = cal.date(from: DateComponents(year: 2026, month: 7, day: 9))!
        XCTAssertTrue(cal.isDate(req.startDate, inSameDayAs: expectedDay),
                      "貸出開始の日は borrow_from の日")
        let hms = cal.dateComponents([.hour, .minute, .second], from: req.startDate)
        XCTAssertFalse(hms.hour == 0 && hms.minute == 0 && hms.second == 0,
                       "13:16の申請なので 0:00 にはならない")
    }

    /// borrow_from 空欄なら、申請日時（created_at そのもの）を使う。
    func testWebBorrowStartDateFallsBackToApplicationMoment() {
        let req = webRequest(from: nil, until: nil)
        XCTAssertEqual(req.startDate.timeIntervalSinceReferenceDate,
                       req.appliedAt.timeIntervalSinceReferenceDate, accuracy: 0.001,
                       "開始日未入力なら申請日時をそのまま使う")
    }

    /// 返却期限は、日付が入っていればその日の 23:59:59。
    func testWebBorrowDueDateIsEndOfChosenDay() throws {
        let req = webRequest(from: "2026-07-09", until: "2026-07-15")
        let due = try XCTUnwrap(req.dueDate)
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: due)
        XCTAssertEqual(c.hour, 23)
        XCTAssertEqual(c.minute, 59)
        XCTAssertEqual(c.second, 59)
    }
}
