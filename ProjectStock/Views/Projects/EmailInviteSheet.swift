import SwiftUI
import CoreData
import CoreImage.CIFilterBuiltins
import UIKit

/// Makes a scannable QR PNG (on a white quiet-zone) of an arbitrary URL, so the
/// invite email carries a code the recipient can scan with a phone even when
/// they read the mail on a PC. Encodes the raw URL (not a タナミル code) so the
/// phone Camera opens it directly.
enum InviteQR {
    static func write(_ string: String) -> URL? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        let code = UIImage(cgImage: cg)
        let pad = scaled.extent.width * 0.1
        let canvas = CGSize(width: scaled.extent.width + pad * 2, height: scaled.extent.height + pad * 2)
        let img = UIGraphicsImageRenderer(size: canvas).image { c in
            UIColor.white.setFill()
            c.fill(CGRect(origin: .zero, size: canvas))
            code.draw(in: CGRect(x: pad, y: pad, width: scaled.extent.width, height: scaled.extent.height))
        }
        guard let data = img.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tanamiru-invite-qr.png")
        do { try data.write(to: url); return url } catch { return nil }
    }
}

/// メールアドレス（相手のApple ID）で1人を確実に招待する動線（1.2.53）。
/// Appleの標準の招待制なので、招待したApple IDでiCloudにサインインして
/// いれば、どの方法でリンクを開いても参加できる。案内文にiCloudの設定手順
/// まで入れて、初めての人でも詰まらないようにする。
struct EmailInviteSheet: View {
    @EnvironmentObject private var container: ServiceContainer
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var project: Project

    @State private var email = ""
    @State private var working = false
    @State private var inviteURL: URL?
    @State private var qrFileURL: URL?
    @State private var showMail = false
    @State private var showShare = false
    @State private var error: PresentableError?

    private var trimmed: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canInvite: Bool { trimmed.contains("@") && trimmed.count >= 3 && !working }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("name@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("inviteEmailField")
                } header: {
                    Text(NSLocalizedString("相手のメールアドレス", comment: ""))
                } footer: {
                    Text(NSLocalizedString("相手が iPhone の iCloud に使っているメールアドレス（Apple ID）を入力してください。ここに入力したアドレスでサインインしている人だけが参加できます。", comment: ""))
                }

                if inviteURL == nil {
                    Section {
                        Button { invite() } label: {
                            HStack {
                                if working {
                                    ProgressView().padding(.trailing, 6)
                                    Text(NSLocalizedString("招待を作成しています…", comment: ""))
                                } else {
                                    Label(NSLocalizedString("この人を招待", comment: ""), systemImage: "person.badge.plus")
                                }
                            }
                        }
                        .disabled(!canInvite)
                        .accessibilityIdentifier("inviteByEmailButton")
                    }
                } else {
                    Section {
                        Label(NSLocalizedString("招待を作成しました。案内を送りましょう。", comment: ""), systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        if MailComposeView.canSend {
                            Button { showMail = true } label: {
                                Label(NSLocalizedString("メールで案内を送る", comment: ""), systemImage: "envelope")
                            }
                        }
                        Button { showShare = true } label: {
                            Label(NSLocalizedString("他のアプリで案内を送る（LINEなど）", comment: ""), systemImage: "square.and.arrow.up")
                        }
                    } footer: {
                        Text(NSLocalizedString("案内には、参加手順・iCloudの設定方法・参加用のQRコードがまとまっています。パソコンで開いた人もQRをスマホで読み取れば参加できます。", comment: ""))
                    }
                }
            }
            .navigationTitle(NSLocalizedString("メールで招待", comment: ""))
            .keyboardDoneBar()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("閉じる", comment: "")) { dismiss() }
                }
            }
            .sheet(isPresented: $showMail) {
                MailComposeView(subject: mailSubject, body: guidance,
                                recipients: [trimmed], attachmentURL: qrFileURL) { dismiss() }
            }
            .sheet(isPresented: $showShare) {
                // LINE などのチャットには短い lineGuidance を送る（メール経路は
                // 丁寧な長文 guidance のまま）。QR画像も一緒に添付する。
                ShareSheet(items: [lineGuidance] + (qrFileURL.map { [$0] } ?? []))
            }
            .errorAlert($error)
        }
    }

    private func invite() {
        working = true
        container.sharing.inviteByEmail(project: project, email: trimmed) { result in
            working = false
            switch result {
            case .success(let url):
                inviteURL = url
                // Encode OUR wrapper link (t.l0l0.app/join) in the QR — scanning
                // it opens タナミル and joins in-app, never the icloud.com
                // web sign-in page.
                qrFileURL = InviteQR.write(CloudSharingService.joinWrapperURL(for: url).absoluteString)
                Haptics.success()
            case .failure(let err):
                error = PresentableError(AppError.shareCreationFailed(err.localizedDescription))
            }
        }
    }

    private var mailSubject: String {
        String(format: NSLocalizedString("在庫アプリ「タナミル」の『%@』に招待します", comment: ""), project.displayName)
    }

    /// 参加手順＋iCloud設定手順を1通にまとめた案内文。手順を細かく刻んで、
    /// 初めての人でも確実に参加まで辿り着けるようにする。
    private var guidance: String {
        String(format: NSLocalizedString("""
在庫アプリ「タナミル」で『%@』に招待しました。下の手順で参加できます。

―――――――――――――
【手順1】アプリを入れる
・App Store で「タナミル」をインストール
%@

【手順2】iPhoneをiCloudにサインイン（重要）
※すでにサインイン済みなら手順3へ。
・「設定」アプリを開く
・いちばん上の「iPhoneにサインイン」をタップ
・このメールを受け取ったアドレス（%@）のApple IDでサインイン
　（同じアドレスでないと参加できません）
・パスワードを入れてサインインを完了する

【手順3】この招待リンクを開く（iPhoneで）
%@
・タップすると、タナミルが開いて参加できます
・このメールをパソコンで見ている場合は、添付の【QRコード】をスマホの
　カメラで読み取ってください（同じくタナミルが開きます）

【うまくいかないとき】
・上の招待リンクを長押しでコピーして、タナミルの「プロジェクト」画面 →
　右上「…」→「招待リンクから参加」に貼り付けてください
　（このリンクは、どこで開いても必ずタナミルに入るようになっています）

―――――――――――――
参加できると、共有プロジェクトが「プロジェクト」一覧に表示されます
（表示まで少し時間がかかることがあります）。
""", comment: ""), project.displayName, AppConfig.appStoreURL, trimmed,
     inviteURL.map { CloudSharingService.joinWrapperURL(for: $0).absoluteString } ?? "")
    }

    /// LINE などのチャット向けの短い案内文。メール版(guidance)は手順を細かく
    /// 刻んだ長文だが、チャットでは長すぎて読まれない。要点だけに絞り、口調も
    /// やわらかくする。LINEの内蔵ブラウザはリンクを開くと icloud.com のサイン
    /// イン画面で行き止まりになりやすいので、「コピーして招待リンクから参加」の
    /// 逃げ道を先頭寄りに置くのがポイント。
    private var lineGuidance: String {
        String(format: NSLocalizedString("""
在庫アプリ「タナミル」の『%@』に招待します🙌

▼参加リンク（iPhoneで開いてね）
%@

・タップするとタナミルが開いて参加できます
・サインイン画面（icloud.com）が出て進めないときは、上のリンクを長押しでコピー →タナミルの「プロジェクト」画面 右上「…」→「招待リンクから参加」に貼り付け
・パソコンの方は、いっしょに送ったQR画像をスマホのカメラで読み取ってね

※アプリを入れていない方はこちら→ %@
※参加には、このメッセージを受け取った端末のiCloud（Apple ID）でのサインインが必要です
""", comment: ""), project.displayName,
     inviteURL.map { CloudSharingService.joinWrapperURL(for: $0).absoluteString } ?? "",
     AppConfig.appStoreURL)
    }
}
