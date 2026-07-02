import XCTest

/// fastlane snapshot 用の App Store スクリーンショット撮影。
/// `-screenshotMode` で起動するとアプリは Pro プラン相当で動作し（キャンバスのロック解除）、
/// 同梱サンプル（夜明けのランナー 35P 完全データ）が初回シードされるため、
/// ネットワーク・サインイン不要で代表画面を撮影できる。
/// iPhone はナビゲーションスタック、iPad(regular) は 3 カラムなので導線を分岐する。
final class ScreenshotUITests: XCTestCase {

    private var app: XCUIApplication!
    /// デバイス種別はテストプロセスの idiom で確実に判定する（UI要素の有無に依存しない）。
    private let isPad = UIDevice.current.userInterfaceIdiom == .pad

    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = false
        // iPad は 3 カラムを一望できる横向きで撮る。縦向きだとサイドバーが
        // オーバーレイになり content に被るため、起動前に回転させておく。
        if isPad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["-screenshotMode"]
        app.launch()
        if isPad {
            // 起動後にも念押しで回転を確定させ、レイアウトを落ち着かせる。
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(2)
        }
    }

    @MainActor
    func testCaptureScreens() {
        // サンプルプロジェクトの一覧が出るまで待つ（初回シード）。
        let sampleRow = app.staticTexts["夜明けのランナー"]
        XCTAssertTrue(sampleRow.waitForExistence(timeout: 25))
        sleep(2)

        if isPad {
            captureOnPad()
        } else {
            captureOnPhone(sampleRow: sampleRow)
        }
    }

    // MARK: iPhone（スタック導線）

    @MainActor
    private func captureOnPhone(sampleRow: XCUIElement) {
        snapshot("01_Home")

        // プロジェクトハブへ。
        sampleRow.tap()
        guard app.staticTexts["ストーリー"].waitForExistence(timeout: 10) else { return }
        sleep(1)

        visit(row: "ストーリー", waitFor: "テーマ", name: "02_Story")
        visit(row: "13フェーズ", waitFor: nil, name: "03_Phases")
        visit(row: "ページプラン", waitFor: nil, name: "04_PagePlan")
        captureCanvas(name: "05_Canvas")
        visit(row: "使用状況", waitFor: nil, name: "06_Usage")
    }

    /// ネームキャンバスは複数コマのページ（P2＝6コマ）を撮る。
    /// 1ページ目は大ゴマ1枚のフックなので、コマ割りが伝わる P2 へ進めてから撮影する。
    @MainActor
    private func captureCanvas(name: String) {
        let cell = app.staticTexts["ネームキャンバス"]
        guard cell.waitForExistence(timeout: 8) else { return }
        cell.tap()
        sleep(1)
        // 「次のページ」（右開きなので進む＝左向きシェブロン）を1回押して P2 へ。
        let next = app.buttons["次のページ"]
        if next.waitForExistence(timeout: 6) { next.tap() }
        sleep(2)
        snapshot(name)
        goBack()
    }

    /// ハブの行をタップ → 描画待ち → 撮影 → 戻る。要素が無ければ静かにスキップ。
    @MainActor
    private func visit(row: String, waitFor marker: String?, name: String) {
        let cell = app.staticTexts[row]
        guard cell.waitForExistence(timeout: 8) else { return }
        cell.tap()
        if let marker {
            _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", marker))
                .firstMatch.waitForExistence(timeout: 8)
        }
        sleep(2)
        snapshot(name)
        goBack()
    }

    @MainActor
    private func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
        sleep(1)
    }

    // MARK: iPad（3カラム導線）

    @MainActor
    private func captureOnPad() {
        // 横向き3カラム（サイドバー｜中央｜インスペクタ）は setUp で確定済み。
        // 分割ビュー全体（一覧＋キャンバス）。
        snapshot("01_Home")

        tapSidebar("13フェーズ", name: "03_Phases")
        tapSidebar("ページプラン", name: "04_PagePlan")   // 右カラムにキャンバスが並ぶ
        tapSidebar("ストーリー", name: "02_Story")
        tapSidebar("使用状況", name: "06_Usage")
    }

    @MainActor
    private func tapSidebar(_ title: String, name: String) {
        // 横向き 3 カラムではサイドバーは常時表示。念のため無ければトグルで開く。
        var item = app.staticTexts[title]
        if !item.exists {
            let toggle = app.navigationBars.buttons.element(boundBy: 0)
            if toggle.exists { toggle.tap(); sleep(1) }
            item = app.staticTexts[title]
        }
        guard item.waitForExistence(timeout: 8) else { return }
        item.tap()
        sleep(2)
        snapshot(name)
    }
}
