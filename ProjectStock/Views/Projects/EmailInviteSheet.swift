import SwiftUI
import CoreData

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
                        Text(NSLocalizedString("案内には、参加手順とiCloudの設定方法をまとめてあります。そのまま送ってください。", comment: ""))
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
                                recipients: [trimmed]) { dismiss() }
            }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: [guidance])
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

【手順3】この招待リンクを開く
%@
・Safari か メッセージ/メール で開くと、タナミルが開いて参加できます
・もしリンクを開いてもうまくいかないときは、リンクを長押しでコピーして、
　タナミルの「プロジェクト」画面 → 右上「…」→「招待リンクから参加」に
　貼り付けてください

―――――――――――――
参加できると、共有プロジェクトが「プロジェクト」一覧に表示されます
（表示まで少し時間がかかることがあります）。
""", comment: ""), project.displayName, AppConfig.appStoreURL, trimmed, inviteURL?.absoluteString ?? "")
    }
}
