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
    @State private var showingEmailInvite = false
    @State private var showingPaywall = false
    // Link invite creates a CKShare server-side (2–4s). Guard against re-taps and
    // show progress — the email/join sheets already do this; this path didn't.
    @State private var preparingInvite = false
    @State private var resettingPublic = false

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
                            // Count only ACCEPTED participants as "sharing with":
                            // a pending (invited-but-not-joined) Apple ID used to
                            // inflate the number, so an owner couldn't tell who had
                            // actually joined.
                            let others = share.participants.filter { $0.role != .owner }
                            let joined = others.filter { $0.acceptanceStatus == .accepted }
                            let pending = others.count - joined.count
                            VStack(alignment: .leading, spacing: 2) {
                                Label(joined.isEmpty
                                        ? NSLocalizedString("まだ参加者はいません。招待リンクを送りましょう。", comment: "")
                                        : String(format: NSLocalizedString("現在 %d 人が参加中", comment: ""), joined.count),
                                      systemImage: "person.2")
                                    .font(.footnote).foregroundColor(.secondary)
                                if pending > 0 {
                                    Text(String(format: NSLocalizedString("招待中（未参加）%d 人", comment: ""), pending))
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                            }

                            // Recovery: "one person can never join / always lands
                            // on icloud.com". Converts the share to a public link
                            // (drops the stuck invite-only slot) so they can join
                            // with their own Apple ID. Also works for recipients
                            // on an old app version that can't open the wrapper.
                            Button {
                                resetToPublic()
                            } label: {
                                HStack {
                                    if resettingPublic { ProgressView().padding(.trailing, 4) }
                                    Label(NSLocalizedString("うまく参加できない人がいるとき（全員リンク参加に切替）", comment: ""),
                                          systemImage: "person.crop.circle.badge.exclamationmark")
                                }
                                .font(.footnote)
                            }
                            .disabled(resettingPublic)
                            .accessibilityIdentifier("resetToPublicButton")
                        }
                    }

                    if permission == .notShared && !RemoteConfig.shared.bool("sharingEnabled", default: true) {
                        // Remote kill-switch: stop NEW shares during an incident
                        // (existing shares keep working — owners keep management).
                        VStack(alignment: .leading, spacing: 6) {
                            Label(NSLocalizedString("共有の新規開始は一時停止中です", comment: ""), systemImage: "wrench.and.screwdriver")
                                .font(.subheadline)
                            Text(NSLocalizedString("メンテナンスのため、新しい共有の開始を一時的に停止しています。しばらくしてからもう一度お試しください。", comment: ""))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    } else if EntitlementService.teamPlanEnabled && permission == .notShared && !entitlements.hasTeamFeatures {
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
                        // PRIMARY: invite one person by their Apple ID email.
                        // This is the reliable Apple-native path — the invited
                        // Apple ID can join no matter how they open the link,
                        // and the guidance email includes the iCloud setup steps.
                        Button {
                            showingEmailInvite = true
                        } label: {
                            Label(NSLocalizedString("メールアドレスで招待（おすすめ）", comment: ""), systemImage: "envelope.badge.person.crop")
                                .font(.body.weight(.semibold))
                                .foregroundColor(Brand.primary)
                        }
                        .accessibilityIdentifier("emailInviteButton")
                        .sheet(isPresented: $showingEmailInvite) { EmailInviteSheet(project: project) }
                        Text(NSLocalizedString("相手のApple ID（メール）を指定して招待します。案内メールにiCloudの設定手順まで入るので、初めての人でも確実です。", comment: ""))
                            .font(.caption2).foregroundColor(.secondary)

                        // SECONDARY: a link anyone signed into iCloud can join.
                        Button {
                            sendInvite()
                        } label: {
                            HStack {
                                if preparingInvite { ProgressView().padding(.trailing, 4) }
                                Label(NSLocalizedString("リンクで招待（誰でも参加可）", comment: ""), systemImage: "link")
                            }
                        }
                        .disabled(preparingInvite)
                        .accessibilityIdentifier("sendInviteButton")
                        .sheet(item: $inviteSheet) { ShareSheet(items: [$0.text]) }
                        Text(NSLocalizedString("このリンクを知っている人は誰でも参加でき、在庫を編集できます。信頼できる相手にだけ送ってください。", comment: ""))
                            .font(.caption2).foregroundColor(.secondary)

                        // Full member/permission management (owner only). Hidden
                        // before a share exists so a not-yet-shared project shows
                        // just the two invite actions, not a third entry point
                        // promising "member management" with no members.
                        if permission == .owner {
                            Button {
                                startShare()
                            } label: {
                                Label(NSLocalizedString("共有設定・メンバー管理", comment: ""),
                                      systemImage: "person.crop.circle.badge.plus")
                            }
                            .accessibilityIdentifier("shareProjectButton")
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

    /// Fix "one person can never join / always lands on icloud.com": convert the
    /// share to a public link and hand back a fresh invite with BOTH the wrapper
    /// link (updated apps) and the raw iCloud link (old apps / paste-to-join).
    private func resetToPublic() {
        resettingPublic = true
        container.sharing.resetToPublicLink(for: project) { result in
            resettingPublic = false
            switch result {
            case .failure(let err):
                error = PresentableError(AppError.shareCreationFailed(err.localizedDescription))
            case .success(let url):
                refreshPermission()
                let wrapper = CloudSharingService.joinWrapperURL(for: url).absoluteString
                let message = String(format: NSLocalizedString("""
在庫アプリ「タナミル」でプロジェクト『%@』に招待します。リンクを知っている人は誰でも参加できます（個別の招待は解除しました）。

【参加リンク】iPhoneでこのリンクを開いてください
%@

【うまく開けない・アプリが古い場合】下のリンクをコピーして、タナミルの「プロジェクト」画面 → 右上「…」→「招待リンクから参加」に貼り付けてください
%@

※どちらも、タナミルを入れたiPhoneなら参加できます。iCloudのサインイン画面で止まってしまう場合は、この新しいリンクで開き直してください。
""", comment: ""), project.displayName, wrapper, url.absoluteString)
                inviteSheet = InviteText(text: message)
                Haptics.success()
            }
        }
    }

    /// Build a ready-to-send invitation that includes BOTH the App Store link
    /// (so a colleague without the app installs it first) and the CloudKit join
    /// link, then present the share sheet. Only available once a share exists.
    ///
    /// Before composing, the share is promoted to link-joinable
    /// (`publicPermission = .readWrite`): the raw URL goes out through LINE /
    /// mail, so a recipient's Apple ID is never a pre-invited participant —
    /// with an invite-only share the link led to an Apple sign-in page and
    /// then a dead end.
    private func sendInvite() {
        preparingInvite = true
        if let share = container.sharing.existingShare(for: project) {
            promoteAndCompose(share)
        } else {
            // One tap does everything: create the share, make it link-joinable,
            // compose the message. Requiring a prior trip through Apple's share
            // sheet left owners with "no share yet" errors (the sheet only
            // creates the share once a send method is chosen there).
            container.sharing.prepareShare(for: project) { result in
                switch result {
                case .success(.existing(let share, _)), .success(.created(let share, _)):
                    refreshPermission()
                    promoteAndCompose(share)
                case .failure(let err):
                    error = PresentableError(err)
                }
            }
        }
    }

    private func promoteAndCompose(_ share: CKShare) {
        guard let url = share.url else {
            // The share exists but its URL hasn't come back from the server yet
            // (happens right after creating the share). Telling the user to
            // "start sharing" here would gaslight them — they just did.
            preparingInvite = false
            error = PresentableError(AppError.shareCreationFailed(
                NSLocalizedString("招待リンクを準備中です。数秒待ってからもう一度お試しください。", comment: "")))
            return
        }
        container.sharing.ensureLinkJoinable(share) { result in
            preparingInvite = false
            switch result {
            case .failure(let err):
                error = PresentableError(AppError.shareCreationFailed(String(
                    format: NSLocalizedString("招待リンクを参加可能にできませんでした（%@）。もう一度お試しください。", comment: ""),
                    err.localizedDescription)))
            case .success:
                let message = String(
                    format: NSLocalizedString("在庫アプリ「タナミル」でプロジェクト『%@』に招待します。\n\n① アプリ未インストールの方は、まずこちらから入手してください：\n%@\n\n② インストール後、この招待リンクを開いて参加してください：\n%@\n\n③ リンクを開いてもサインイン画面から進めないとき（LINEなど）は、②のリンクを長押しでコピーし、タナミルの「プロジェクト」画面右上の「…」→「招待リンクから参加」に貼り付けてください。", comment: ""),
                    project.displayName, AppConfig.appStoreURL, url.absoluteString)
                inviteSheet = InviteText(text: message)
            }
        }
    }
}

/// Identifiable wrapper so an invitation message can drive `.sheet(item:)`.
struct InviteText: Identifiable {
    let id = UUID()
    let text: String
}
