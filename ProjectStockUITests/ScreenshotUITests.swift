import XCTest

/// Generates App Store screenshots via fastlane snapshot. Launches with a seeded
/// demo project (`-snapshotData`) on the deterministic in-memory store
/// (`-uiTesting`) and captures the main tabs plus one drill-in.
final class ScreenshotUITests: XCTestCase {

    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["-uiTesting", "-snapshotData"]
        app.launch()
    }

    @MainActor
    func testCaptureScreens() {
        let app = XCUIApplication()

        // Home (dashboard). The seed runs on first appear; give it a moment.
        XCTAssertTrue(app.tabBars.buttons["ホーム"].waitForExistence(timeout: 20))
        sleep(2)
        snapshot("01_Home")

        // Projects list — shows the seeded "サンプル工房".
        app.tabBars.buttons["プロジェクト"].tap()
        _ = app.staticTexts["サンプル工房"].waitForExistence(timeout: 10)
        snapshot("02_Projects")

        // Drill into the project to show folders / products / QR entry points.
        if app.staticTexts["サンプル工房"].exists {
            app.staticTexts["サンプル工房"].tap()
            sleep(2)
            snapshot("03_ProjectDetail")
            app.navigationBars.buttons.element(boundBy: 0).tap() // back
        }

        // Activity — populated history from the seeded events.
        if app.tabBars.buttons["活動"].exists {
            app.tabBars.buttons["活動"].tap()
            sleep(1)
            snapshot("04_Activity")
        }

        // Settings.
        app.tabBars.buttons["設定"].tap()
        sleep(1)
        snapshot("05_Settings")
    }
}
