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

    // 1.2.55: 招待を自前ドメイン t.l0l0.app/join?s=… に包み、QR/リンクを開いても
    // 必ずアプリの参加処理に入る（icloud.comのログインに収束しない）。
    func testJoinWrapperRoundTrip() {
        let share = URL(string: "https://www.icloud.com/share/0abcDEF123ghi")!
        let wrapper = CloudSharingService.joinWrapperURL(for: share)
        XCTAssertEqual(wrapper.host, "t.l0l0.app")
        XCTAssertEqual(wrapper.path, "/join")

        let back = RootTabView.shareURL(fromJoinLink: wrapper)
        XCTAssertEqual(back?.absoluteString, share.absoluteString,
                       "wrapperを解いて元のicloud共有URLに戻る")
    }

    func testJoinLinkRejectsNonJoinAndForeignHosts() {
        // 借用リンク（/<code>）は招待として拾わない
        XCTAssertNil(RootTabView.shareURL(fromJoinLink: URL(string: "https://t.l0l0.app/TNM-0001")!))
        // 別ホストのjoinも拾わない
        XCTAssertNil(RootTabView.shareURL(fromJoinLink: URL(string: "https://example.com/join?s=https://www.icloud.com/share/x")!))
    }
}
