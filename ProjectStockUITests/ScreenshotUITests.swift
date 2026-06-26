import XCTest

/// Captures raw App Store screenshots via fastlane snapshot. Launches with three
/// seeded industry demo projects (`-snapshotData`) on the deterministic
/// in-memory store (`-uiTesting`) and visits varied, populated screens.
/// The raw captures are framed/captioned afterwards (PIL compositor), then
/// uploaded — so here we just need clean, representative screens.
final class ScreenshotUITests: XCTestCase {

    private var app: XCUIApplication!

    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["-uiTesting", "-snapshotData"]
        app.launch()
    }

    @MainActor
    func testCaptureScreens() {
        // Home dashboard — aggregates all three projects (low stock, overdue,
        // expiring lots). The seed runs on first appear; give it a moment.
        XCTAssertTrue(app.tabBars.buttons["ホーム"].waitForExistence(timeout: 25))
        sleep(3)
        snapshot("01_Home")

        // Projects list — three different industries.
        app.tabBars.buttons["プロジェクト"].tap()
        _ = app.staticTexts["サンプル営業部"].waitForExistence(timeout: 12)
        sleep(1)
        snapshot("02_Projects")

        // Activity / history.
        if app.tabBars.buttons["活動"].exists {
            app.tabBars.buttons["活動"].tap()
            sleep(1)
            snapshot("03_Activity")
        }

        // Sales sample detail — individually tracked units with a loan out.
        drillProduct(project: "サンプル営業部", product: "フローリング オーク", name: "04_Sales")
        // Café lot detail — lots with expiry badges.
        drillProduct(project: "カフェ・ハル 在庫", product: "コーヒー豆 ブレンド", name: "05_Cafe")

        // Factory: project product list (06), then a quantity product detail (07).
        app.tabBars.buttons["プロジェクト"].tap()
        backToProjectsRoot()
        if app.staticTexts["第一工場 整備課"].waitForExistence(timeout: 10) {
            app.staticTexts["第一工場 整備課"].tap()
            sleep(2)
            snapshot("06_FactoryList")
            let bolt = app.staticTexts["M4 ボルト"]
            if bolt.waitForExistence(timeout: 8) {
                bolt.tap()
                _ = app.buttons["receiveButton"].waitForExistence(timeout: 8)
                sleep(1)
                snapshot("07_FactoryQty")
            }
        }

        // Settings.
        app.tabBars.buttons["設定"].tap()
        sleep(1)
        snapshot("08_Settings")
    }

    @MainActor
    private func drillProduct(project: String, product: String, name: String) {
        app.tabBars.buttons["プロジェクト"].tap()
        backToProjectsRoot()
        let pj = app.staticTexts[project]
        guard pj.waitForExistence(timeout: 10) else { return }
        pj.tap()
        let pr = app.staticTexts[product]
        guard pr.waitForExistence(timeout: 10) else { return }
        pr.tap()
        sleep(2)
        snapshot(name)
    }

    /// Pops the Projects navigation stack back to its root list.
    @MainActor
    private func backToProjectsRoot() {
        for _ in 0..<4 {
            if app.navigationBars["プロジェクト"].exists { return }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap(); sleep(1) } else { return }
        }
    }
}
