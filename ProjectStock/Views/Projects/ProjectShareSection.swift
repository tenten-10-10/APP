import SwiftUI
import CloudKit
import CoreData

/// Share segment of the project detail (spec §10, §12.3). Surfaces account
/// state, lets the owner start/manage a CKShare, and reflects participant
/// permission. Read-only participants get an informational view only.
struct ProjectShareSection: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var syncMonitor: CloudKitSyncMonitor
    @EnvironmentObject private var entitlements: EntitlementService
    @ObservedObject var project: Project
    @Binding var permission: SharePermission

    @State private var error: PresentableError?
    @State private var inviteSheet: InviteText?
    @State private var showingPaywall = false

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
                    if permission == .owner {
                        // Participation at a glance — without this the owner has
                        // no way to tell whether anyone actually joined.
                        if let share = container.sharing.existingShare(for: project) {
                            let others = share.participants.filter { $0.role != .owner }
                            Label(others.isEmpty
                                    ? NSLocalizedString("まだ参加者はいません。招待リンクを送りましょう。", comment: "")
                                    : String(format: NSLocalizedString("現在 %d 人と共有中", comment: ""), others.count),
                                  systemImage: "person.2")
                                .font(.footnote).foregroundColor(.secondary)
                        }
                        // The friendly invite (App Store link + join link in one
                        // message) is the PRIMARY action for non-technical users;
                        // Apple's management sheet is secondary.
                        Button {
                            sendInvite()
                        } label: {
                            Label(NSLocalizedString("招待リンクを送る", comment: ""), systemImage: "envelope")
                                .font(.body.weight(.semibold))
                                .foregroundColor(Brand.primary)
                        }
                        .accessibilityIdentifier("sendInviteButton")
                        .sheet(item: $inviteSheet) { ShareSheet(items: [$0.text]) }
                        Text(NSLocalizedString("アプリの入手先と参加リンクをまとめて送信します。", comment: ""))
                            .font(.caption2).foregroundColor(.secondary)
                    }

                    if permission == .notShared && !entitlements.hasTeamFeatures {
                        // Starting a NEW share requires タナミル チーム. Existing
                        // shares (created before the paywall, or unlocked via an
                        // offer code) are untouched, and participants join free.
                        Button {
                            showingPaywall = true
                        } label: {
                            Label(NSLocalizedString("このプロジェクトを共有（チーム機能）", comment: ""),
                                  systemImage: "person.crop.circle.badge.plus")
                        }
                        .accessibilityIdentifier("shareProjectButton")
                        Text(NSLocalizedString("共有には「タナミル チーム」への登録が必要です（2週間無料）。招待コードをお持ちの方も、ここから引き換えできます。参加する側は無料です。", comment: ""))
                            .font(.caption2).foregroundColor(.secondary)
                    } else {
                        Button {
                            startShare()
                        } label: {
                            Label(permission == .owner ? NSLocalizedString("共有設定・メンバー管理", comment: "") : NSLocalizedString("このプロジェクトを共有", comment: ""),
                                  systemImage: "person.crop.circle.badge.plus")
                        }
                        .accessibilityIdentifier("shareProjectButton")

                        if permission == .notShared {
                            Text(NSLocalizedString("押すと参加リンクを作成します。リンクを開いた相手は、このプロジェクトを一緒に使えるようになります。", comment: ""))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text(NSLocalizedString("iCloud共有", comment: ""))
        } footer: {
            Text(NSLocalizedString("プロジェクトと、その中のフォルダ・製品・場所・在庫イベントがまとめて共有されます。共有は「今すぐ同期」ではなく、変更が自動で反映されます。", comment: ""))
                .font(.caption2)
        }
        .errorAlert($error)
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .onAppear { syncMonitor.refreshAccountStatus() }
    }

    private func startShare() {
        // Present the sharing controller DIRECTLY via UIKit (see
        // CloudSharePresenter) rather than through a SwiftUI `.sheet`. The share
        // section re-renders on every CloudKit sync event (it observes
        // syncMonitor), and a `.sheet`-hosted UICloudSharingController is torn
        // down by those re-renders — that is the "flashes open then closes on
        // the first tap" bug. A direct UIKit presentation is immune to it.
        //
        // existingShare == nil → the controller creates the CKShare itself at
        // the right time (preparationHandler); otherwise it opens in "manage"
        // mode for the existing share.
        let existing = container.sharing.existingShare(for: project)
        CloudSharePresenter.present(persistence: container.persistence,
                                    objectID: project.objectID,
                                    title: project.displayName,
                                    existingShare: existing,
                                    syncMonitor: syncMonitor,
                                    onSaved: refreshPermission,
                                    onStopSharing: refreshPermission,
                                    onError: { err in
                                        // Surface the REAL nested reason (the
                                        // per-record CloudKit server message).
                                        error = PresentableError(AppError.shareCreationFailed(
                                            CloudKitErrorMapper.rawDescription(for: err)))
                                    })
    }

    private func refreshPermission() {
        permission = container.sharing.permission(for: project)
    }

    /// Build a ready-to-send invitation that includes BOTH the App Store link
    /// (so a colleague without the app installs it first) and the CloudKit join
    /// link, then present the share sheet. Only available once a share exists.
    private func sendInvite() {
        guard let share = container.sharing.existingShare(for: project) else {
            error = PresentableError(AppError.shareCreationFailed(
                NSLocalizedString("まだ共有が開始されていません。「このプロジェクトを共有」から共有を開始してください。", comment: "")))
            return
        }
        guard let url = share.url else {
            // The share exists but its URL hasn't come back from the server yet
            // (happens right after creating the share). Telling the user to
            // "start sharing" here would gaslight them — they just did.
            error = PresentableError(AppError.shareCreationFailed(
                NSLocalizedString("招待リンクを準備中です。数秒待ってからもう一度お試しください。", comment: "")))
            return
        }
        let message = String(
            format: NSLocalizedString("在庫アプリ「タナミル」でプロジェクト『%@』に招待します。\n\n① アプリ未インストールの方は、まずこちらから入手してください：\n%@\n\n② インストール後、この招待リンクを開いて参加してください：\n%@", comment: ""),
            project.displayName, AppConfig.appStoreURL, url.absoluteString)
        inviteSheet = InviteText(text: message)
    }
}

/// Identifiable wrapper so an invitation message can drive `.sheet(item:)`.
struct InviteText: Identifiable {
    let id = UUID()
    let text: String
}
