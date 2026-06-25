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

    var body: some View {
        Section {
            SharePermissionBadge(permission: permission)

            if !container.persistence.cloudKitEnabled {
                Text(AccountState.cloudKitDisabled.localizedMessage)
                    .font(.footnote).foregroundColor(.secondary)
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
}

struct SharePresentation: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}
