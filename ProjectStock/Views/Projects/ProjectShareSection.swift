import SwiftUI
import CloudKit
import CoreData

/// Share segment of the project detail (spec §10, §12.3). Surfaces account
/// state, lets the owner start/manage a CKShare, and reflects participant
/// permission. Read-only participants get an informational view only.
struct ProjectShareSection: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var syncMonitor: CloudKitSyncMonitor
    @ObservedObject var project: Project
    @Binding var permission: SharePermission

    @State private var presentation: SharePresentation?
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
            } else if syncMonitor.accountState == .noAccount || syncMonitor.accountState == .restricted {
                // Only block for a DEFINITIVE account problem (not signed in /
                // restricted). We do NOT block on `.couldNotDetermine` /
                // `.temporarilyUnavailable`: those are transient and used to
                // hide the share button even though sync was clearly working.
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
                        Label(permission == .owner ? NSLocalizedString("共有を管理", comment: "") : NSLocalizedString("このプロジェクトを共有", comment: ""),
                              systemImage: "person.crop.circle.badge.plus")
                    }
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
            CloudSharingControllerView(persistence: container.persistence,
                                       objectID: item.objectID,
                                       title: project.displayName,
                                       existingShare: item.existingShare,
                                       onSaved: refreshPermission,
                                       onStopSharing: refreshPermission,
                                       onError: { err in
                                           // Surface the REAL nested reason (CloudKit
                                           // per-record server message), not just
                                           // "Failed to modify some records".
                                           error = PresentableError(AppError.shareCreationFailed(
                                               CloudKitErrorMapper.rawDescription(for: err)))
                                       })
        }
        .errorAlert($error)
        .onAppear { syncMonitor.refreshAccountStatus() }
    }

    private func startShare() {
        // Present the sharing controller directly. For a not-yet-shared project
        // we pass existingShare = nil so the controller creates the CKShare
        // itself at the correct time (Apple's preparationHandler pattern, see
        // CloudSharingControllerView); for an already-shared one we hand it the
        // existing CKShare so it opens in "manage" mode.
        presentation = SharePresentation(objectID: project.objectID,
                                         existingShare: container.sharing.existingShare(for: project))
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
    let objectID: NSManagedObjectID
    let existingShare: CKShare?
}

/// Identifiable wrapper so an invitation message can drive `.sheet(item:)`.
struct InviteText: Identifiable {
    let id = UUID()
    let text: String
}
