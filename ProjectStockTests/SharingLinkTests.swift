import XCTest
@testable import ProjectStock

/// 1.2.52: 「招待リンクから参加」の入力解釈。招待メッセージ全文の貼り付け、
/// 未エンコードの日本語フラグメント付きリンク、無関係なURLの拒否を確認する。
final class SharingLinkTests: XCTestCase {

    func testExtractsLinkFromWholeInviteMessage() {
        let message = """
        在庫アプリ「タナミル」でプロジェクト『備品管理』に招待します。

        ① アプリ未インストールの方は、まずこちらから入手してください：
        https://apps.apple.com/app/id6784470155

        ② インストール後、この招待リンクを開いて参加してください：
        https://www.icloud.com/share/0abcDEF123ghi
        """
        let url = CloudSharingService.extractShareURL(from: message)
        XCTAssertEqual(url?.host, "www.icloud.com")
        XCTAssertTrue(url?.path.hasPrefix("/share/") ?? false,
                      "App Storeリンクではなく共有リンクを拾う")
    }

    func testExtractsBareLinkWithWhitespace() {
        let url = CloudSharingService.extractShareURL(from: "  https://www.icloud.com/share/0abc123\n")
        XCTAssertEqual(url?.absoluteString, "https://www.icloud.com/share/0abc123")
    }

    func testUnencodedJapaneseFragmentFallsBackToToken() {
        // 手動コピーでフラグメントが未エンコードのまま貼られても、#の前の
        // トークンだけで参加できる。
        let url = CloudSharingService.extractShareURL(from: "https://www.icloud.com/share/0abc123#備品管理")
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.absoluteString.hasPrefix("https://www.icloud.com/share/0abc123") ?? false)
    }

    func testRejectsForeignAndEmptyInput() {
        XCTAssertNil(CloudSharingService.extractShareURL(from: "https://example.com/share/abc"))
        XCTAssertNil(CloudSharingService.extractShareURL(from: "ただのテキスト"))
        XCTAssertNil(CloudSharingService.extractShareURL(from: ""))
    }
}
