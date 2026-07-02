import SwiftUI
import CloudKit

/// Share segment of the project detail (spec §10, §12.3). Surfaces account
/// state, lets the owner start/manage a CKShare, and reflects participant
/// permission. Read-only participants get an informational view only.
struct ProjectShareSection: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var syncMonitor: CloudKitSyncMonitor
    @ObservedObject var project: Project
    @Binding var permission: SharePermission

    @State private var presentation: SharePresentation?
    @State private var preparing = false
    @State private var error: PresentableError?
    @State private var inviteSheet: InviteText?

    var body: some View {
        Section {
            SharePermissionBadge(permission: permission)

            if !container.persistence.cloudKitEnabled {
                Text(AccountState.cloudKitDisabled.localizedMessage)
                    .font(.footnote).foregroundColor(.secondary)
            } else if !container.persistence.cloudKitActive {
                VStack(alignment: .leading, spacing: 6) {
                    Label(NSLocalizedString("iCloud同期が開始できていません", comment: ""), systemImage: "icloud.slash")
                        .font(.subheadline)
                    Text(NSLocalizedString("アプリを一度終了して開き直すと再接続します。設定 > Apple ID > iCloud で「タナミル」がオンになっているかもご確認ください。", comment: ""))
                        .font(.footnote).foregroundColor(.secondary)
                }
            } else if syncMonitor.accountState != .available {
                VStack(alignment: .leading, spacing: 6) {
                    Label(NSLocalizedString("iCloudが必要です", comment: ""), systemImage: "icloud.slash")
                        .font(.subheadline)
                    Text(syncMonitor.accountState.localizedMessage)
                        .font(.footnote).foregroundColor(.secondary)
                    Button(NSLocalizedString("状態を再確認", comment: "")) { syncMonitor.refreshAccountStatus() }
                        .font(.footnote)
                }
            } else {
                switch permission {
                case .readOnly:
                    Text(NSLocalizedString("このプロジェクトは読み取り専用で共有されています。編集はできません。", comment: ""))
                        .font(.footnote).foregroundColor(.secondary)
                case .readWrite:
                    Text(NSLocalizedString("このプロジェクトは編集可能な権限で共有されています。", comment: ""))
                        .font(.footnote).foregroundColor(.secondary)
                case .owner, .notShared:
                    Button {
                        startShare()
                    } label: {
                        if preparing {
                            ProgressView()
                        } else {
                            Label(permission == .owner ? NSLocalizedString("共有を管理", comment: "") : NSLocalizedString("このプロジェクトを共有", comment: ""),
                                  systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                    .disabled(preparing)
                    .accessibilityIdentifier("shareProjectButton")

                    if permission == .owner {
                        Button {
                            sendInvite()
                        } label: {
                            Label(NSLocalizedString("招待リンクを送る", comment: ""), systemImage: "envelope")
                        }
                        .accessibilityIdentifier("sendInviteButton")
                        .sheet(item: $inviteSheet) { ShareSheet(items: [$0.text]) }
                    }
                }
            }
        } header: {
            Text(NSLocalizedString("iCloud共有", comment: ""))
        } footer: {
            Text(NSLocalizedString("プロジェクトと、その中のフォルダ・製品・場所・在庫イベントがまとめて共有されます。共有は「今すぐ同期」ではなく、変更が自動で反映されます。", comment: ""))
                .font(.caption2)
        }
        .sheet(item: $presentation) { item in
            CloudSharingControllerView(share: item.share, container: item.container,
                                       title: project.displayName,
                                       onSaved: refreshPermission,
                                       onStopSharing: refreshPermission,
                                       onError: { error = PresentableError($0) })
        }
        .errorAlert($error)
    }

    private func startShare() {
        preparing = true
        container.sharing.prepareShare(for: project) { result in
            preparing = false
            switch result {
            case .success(let prep):
                let (share, ckContainer): (CKShare, CKContainer)
                switch prep {
                case .existing(let s, let c): (share, ckContainer) = (s, c)
                case .created(let s, let c):  (share, ckContainer) = (s, c)
                }
                presentation = SharePresentation(share: share, container: ckContainer)
            case .failure(let err):
                error = PresentableError(err)
            }
        }
    }

    private func refreshPermission() {
        permission = container.sharing.permission(for: project)
    }

    /// Build a ready-to-send invitation that includes BOTH the App Store link
    /// (so a colleague without the app installs it first) and the CloudKit join
    /// link, then present the share sheet. Only available once a share exists.
    private func sendInvite() {
        guard let share = container.sharing.existingShare(for: project),
              let url = share.url else {
            error = PresentableError(AppError.shareCreationFailed(
                NSLocalizedString("招待リンクをまだ作成できません。先に「共有を管理」から共有を開始してください。", comment: "")))
            return
        }
        let message = String(
            format: NSLocalizedString("在庫アプリ「タナミル」でプロジェクト『%@』に招待します。\n\n① アプリ未インストールの方は、まずこちらから入手してください：\n%@\n\n② インストール後、この招待リンクを開いて参加してください：\n%@", comment: ""),
            project.displayName, AppConfig.appStoreURL, url.absoluteString)
        inviteSheet = InviteText(text: message)
    }
}

struct SharePresentation: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

/// Identifiable wrapper so an invitation message can drive `.sheet(item:)`.
struct InviteText: Identifiable {
    let id = UUID()
    let text: String
}
