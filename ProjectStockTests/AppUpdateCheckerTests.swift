import XCTest
@testable import ProjectStock

final class AppUpdateCheckerTests: XCTestCase {

    func testIsNewerComparesNumericComponents() {
        XCTAssertTrue(AppUpdateChecker.isNewer("1.2.63", than: "1.2.62"))
        XCTAssertTrue(AppUpdateChecker.isNewer("1.3.0", than: "1.2.63"))
        XCTAssertTrue(AppUpdateChecker.isNewer("1.2.10", than: "1.2.9"), "数値比較（文字列比較ではない）")
        XCTAssertTrue(AppUpdateChecker.isNewer("1.2", than: "1.1.9"))
    }

    func testIsNewerFalseWhenSameOrOlder() {
        XCTAssertFalse(AppUpdateChecker.isNewer("1.2.63", than: "1.2.63"), "同一版はアップデートなし")
        XCTAssertFalse(AppUpdateChecker.isNewer("1.2.62", than: "1.2.63"))
        XCTAssertFalse(AppUpdateChecker.isNewer("1.2.9", than: "1.2.10"))
        XCTAssertFalse(AppUpdateChecker.isNewer("1.2.0", than: "1.2"), "1.2.0 と 1.2 は同一")
    }

    func testStoreVersionParsesLookupPayload() throws {
        let json = #"{"resultCount":1,"results":[{"version":"1.2.70","trackViewUrl":"https://apps.apple.com/app/id6784470155"}]}"#
        let data = Data(json.utf8)
        XCTAssertEqual(AppUpdateChecker.storeVersion(from: data), "1.2.70")
    }

    func testStoreVersionNilOnEmptyResults() {
        let data = Data(#"{"resultCount":0,"results":[]}"#.utf8)
        XCTAssertNil(AppUpdateChecker.storeVersion(from: data))
    }
}
