import XCTest

/// UI tests run against an in-memory store with a mock scanner (the app reads
/// the `-uiTesting` launch argument). They cover the core flows from spec §17.
final class ProjectStockUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    func testLaunchShowsProjectsTab() {
        XCTAssertTrue(app.navigationBars["プロジェクト"].waitForExistence(timeout: 5))
    }

    func testCreateProject() {
        app.buttons["createProjectButton"].tap()
        let nameField = app.textFields["projectNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("テスト工房")
        app.buttons["saveProjectButton"].tap()
        XCTAssertTrue(app.staticTexts["テスト工房"].waitForExistence(timeout: 3))
    }

    func testCreateProjectAndProductWithStock() {
        // Create the project.
        app.buttons["createProjectButton"].tap()
        let nameField = app.textFields["projectNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap(); nameField.typeText("在庫テスト")
        app.buttons["saveProjectButton"].tap()

        // Open it.
        app.staticTexts["在庫テスト"].tap()

        // Add a product.
        let addProduct = app.buttons["addProductButton"]
        XCTAssertTrue(addProduct.waitForExistence(timeout: 3))
        addProduct.tap()

        let productName = app.textFields["productNameField"]
        XCTAssertTrue(productName.waitForExistence(timeout: 3))
        productName.tap(); productName.typeText("ボルト")

        let initial = app.textFields["initialQuantityField"]
        if initial.exists { initial.tap(); initial.typeText("25") }

        app.buttons["saveProductButton"].tap()
        XCTAssertTrue(app.staticTexts["ボルト"].waitForExistence(timeout: 3))
    }

    func testScanTabShowsMockScanner() {
        app.tabBars.buttons["スキャン"].tap()
        XCTAssertTrue(app.textFields["mockScanField"].waitForExistence(timeout: 3),
                      "UIテストではモックスキャナが表示される")
    }

    func testSettingsTabReachable() {
        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(app.textFields["operatorNameField"].waitForExistence(timeout: 3))
    }
}
