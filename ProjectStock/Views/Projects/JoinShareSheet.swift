import SwiftUI
import UIKit

/// Manual recovery path for share invitations (1.2.52). In-app browsers
/// (LINE など) open the iCloud invite URL as a plain web page — the recipient
/// signs in to their Apple Account and hits a dead end, because the invitation
/// never reaches the app. Here they paste the copied link and the app fetches
/// and accepts the share directly, regardless of where the link was opened.
struct JoinShareSheet: View {
    @EnvironmentObject private var container: ServiceContainer
    @Environment(\.dismiss) private var dismiss

    @State private var link = ""
    @State private var joining = false
    @State private var joined = false
    @State private var error: PresentableError?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("https://www.icloud.com/share/…", text: $link)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("joinShareLinkField")
                    Button {
                        if let pasted = UIPasteboard.general.string { link = pasted }
                    } label: {
                        Label(NSLocalizedString("コピーしたリンクを貼り付け", comment: ""), systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text(NSLocalizedString("招待リンク", comment: ""))
                } footer: {
                    Text(NSLocalizedString("受け取った招待リンク（icloud.com/share/…）を貼り付けてください。招待メッセージごと貼り付けても大丈夫です。LINEなどでリンクを開いてもサインイン画面から進めないときは、リンクを長押しでコピーして、ここから参加できます。", comment: ""))
                }

                Section {
                    Button { join() } label: {
                        HStack {
                            if joining {
                                ProgressView().padding(.trailing, 6)
                                Text(NSLocalizedString("参加しています…", comment: ""))
                            } else {
                                Label(NSLocalizedString("参加する", comment: ""), systemImage: "person.badge.plus")
                            }
                        }
                    }
                    .disabled(joining || joined || shareURL == nil)
                    .accessibilityIdentifier("joinShareButton")
                }

                if joined {
                    Section {
                        Label(NSLocalizedString("参加しました。共有プロジェクトは、同期が終わると「プロジェクト」一覧に表示されます。", comment: ""),
                              systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("招待リンクから参加", comment: ""))
            .keyboardDoneBar()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("閉じる", comment: "")) { dismiss() }
                }
            }
            .errorAlert($error)
        }
    }

    private var shareURL: URL? { CloudSharingService.extractShareURL(from: link) }

    private func join() {
        guard let url = shareURL else { return }
        joining = true
        container.sharing.joinShare(from: url) { result in
            joining = false
            switch result {
            case .success:
                joined = true
                Haptics.success()
            case .failure(let err):
                error = PresentableError(AppError.shareCreationFailed(err.localizedDescription))
            }
        }
    }
}
