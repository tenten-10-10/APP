import Foundation
import CoreData
import CloudKit
import Combine

/// A project's share permission from the local user's point of view.
public enum SharePermission: Equatable {
    case notShared     // private, owned, not shared with anyone
    case owner         // owned and shared by this user
    case readWrite     // shared TO this user with edit rights
    case readOnly      // shared TO this user, view only

    /// Whether the local user may mutate the project graph.
    public var canEdit: Bool {
        switch self {
        case .notShared, .owner, .readWrite: return true
        case .readOnly: return false
        }
    }

    public var badgeTitle: String {
        switch self {
        case .notShared: return NSLocalizedString("ローカル", comment: "")
        case .owner:     return NSLocalizedString("共有（所有者）", comment: "")
        case .readWrite: return NSLocalizedString("共有（編集可）", comment: "")
        case .readOnly:  return NSLocalizedString("共有（閲覧のみ）", comment: "")
        }
    }
}

/// Wraps CloudKit sharing for projects (spec §10). Creation, lookup, permission
/// detection and invitation acceptance funnel through here so the UI never
/// touches CloudKit directly. Guards prevent duplicate in-flight shares.
final class CloudSharingService: ObservableObject {

    let persistence: PersistenceController
    let router: StoreRouter
    let projectService: ProjectService

    /// Object IDs currently having a share created, to prevent double taps.
    @Published private(set) var inFlight: Set<NSManagedObjectID> = []

    init(persistence: PersistenceController, router: StoreRouter, projectService: ProjectService) {
        self.persistence = persistence
        self.router = router
        self.projectService = projectService
    }

    var ckContainer: CKContainer {
        CKContainer(identifier: AppConfig.cloudKitContainerIdentifier)
    }

    // MARK: - State queries

    func existingShare(for project: Project) -> CKShare? {
        guard persistence.cloudKitEnabled else { return nil }
        let shares = try? persistence.container.fetchShares(matching: [project.objectID])
        return shares?[project.objectID]
    }

    func isShared(_ project: Project) -> Bool {
        existingShare(for: project) != nil || router.isShared(project)
    }

    /// The local user's permission on a project.
    func permission(for project: Project) -> SharePermission {
        guard persistence.cloudKitEnabled else { return .notShared }
        let participant = router.isShared(project) // lives in the shared store → shared TO us
        if participant {
            if let share = existingShare(for: project),
               let me = share.currentUserParticipant {
                return me.permission == .readWrite ? .readWrite : .readOnly
            }
            return .readOnly
        } else {
            return existingShare(for: project) != nil ? .owner : .notShared
        }
    }

    func canEdit(_ project: Project) -> Bool {
        permission(for: project).canEdit
    }

    /// Batched share state for a list of projects, in ONE `fetchShares` call
    /// (per-row `permission(for:)` would fetch shares once per row on every
    /// scroll). Returns only shared projects — owner (I shared it out) and
    /// participant (shared to me); non-shared projects are omitted.
    func sharePermissions(among projects: [Project]) -> [NSManagedObjectID: SharePermission] {
        guard persistence.cloudKitEnabled, !projects.isEmpty else { return [:] }
        let shares = (try? persistence.container.fetchShares(matching: projects.map(\.objectID))) ?? [:]
        var result: [NSManagedObjectID: SharePermission] = [:]
        for project in projects {
            if router.isShared(project) { // lives in the shared store → shared TO us
                if let share = shares[project.objectID], let me = share.currentUserParticipant {
                    result[project.objectID] = me.permission == .readWrite ? .readWrite : .readOnly
                } else {
                    result[project.objectID] = .readOnly
                }
            } else if shares[project.objectID] != nil {
                result[project.objectID] = .owner
            }
        }
        return result
    }

    /// Nil-safe variant: an object with no project is treated as locally
    /// editable (avoids constructing throwaway managed objects in views).
    func canEdit(_ project: Project?) -> Bool {
        guard let project else { return true }
        return permission(for: project).canEdit
    }

    // MARK: - Share creation (spec §10)

    enum SharePreparation {
        case existing(CKShare, CKContainer)
        case created(CKShare, CKContainer)
    }

    /// Validate readiness, then return an existing share or create a fresh one
    /// associating the project + its whole object graph with a CKShare.
    func prepareShare(for project: Project,
                      completion: @escaping (Result<SharePreparation, Error>) -> Void) {
        guard persistence.cloudKitEnabled else {
            completion(.failure(AppError.shareCreationFailed(NSLocalizedString("このビルドでは共有を利用できません。", comment: ""))))
            return
        }
        guard persistence.cloudKitActive else {
            completion(.failure(AppError.shareCreationFailed(NSLocalizedString("iCloud同期を開始できていないため、共有を作成できません。アプリを一度終了して開き直すと再接続します。設定 > Apple ID > iCloud で「タナミル」がオンになっているかもご確認ください。", comment: ""))))
            return
        }
        do {
            try projectService.validateShareReadiness(project)
        } catch {
            completion(.failure(error)); return
        }

        if let share = existingShare(for: project) {
            completion(.success(.existing(share, ckContainer)))
            return
        }

        guard !inFlight.contains(project.objectID) else { return } // already creating
        inFlight.insert(project.objectID)

        persistence.container.share([project], to: nil) { [weak self] _, share, container, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(project.objectID)
                if let error = error {
                    let raw = error.localizedDescription
                    // The most common failure is that CloudKit mirroring never
                    // finished initialising — almost always because the
                    // container's schema isn't fully deployed to the Production
                    // environment yet. Show a clean, honest message instead of
                    // the raw multi-line CKError dump (the detail is in
                    // 設定 > 診断 for the developer).
                    let mirroringNotReady = raw.contains("mirroring delegate never successfully initialized")
                        || raw.contains("production schema")
                        || raw.contains("Cannot create new type")
                    let message = mirroringNotReady
                        ? NSLocalizedString("iCloud共有の準備がまだ完了していないため、共有できません。しばらく待ってから、もう一度お試しください。（状態は「設定 > 診断」で確認できます）", comment: "")
                        : String(format: NSLocalizedString("共有を開始できませんでした（%@）。アプリを一度終了して開き直し、もう一度お試しください。", comment: ""), raw)
                    completion(.failure(AppError.shareCreationFailed(message))); return
                }
                guard let share = share, let container = container else {
                    completion(.failure(AppError.shareCreationFailed(NSLocalizedString("共有レコードを作成できませんでした。", comment: ""))))
                    return
                }
                share[CKShare.SystemFieldKey.title] = project.displayName as CKRecordValue
                completion(.success(.created(share, container)))
            }
        }
    }

    // MARK: - Invitation acceptance (spec §10)

    /// Result of the most recent automatic invitation acceptance, published so
    /// the UI can tell the recipient what happened. Before 1.2.52 the result
    /// was silently discarded — a failed acceptance looked identical to
    /// "nothing happened at all".
    @Published var acceptFeedback: AcceptFeedback?

    struct AcceptFeedback: Identifiable, Equatable {
        let id = UUID()
        let success: Bool
        let message: String
    }

    /// Accept an incoming share invitation into the SHARED store.
    func acceptShare(metadata: CKShare.Metadata, completion: @escaping (Result<Void, Error>) -> Void) {
        guard persistence.cloudKitEnabled, let sharedStore = persistence.sharedStore else {
            completion(.failure(AppError.shareCreationFailed(NSLocalizedString("共有ストアが利用できません。", comment: ""))))
            return
        }
        persistence.container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)) }
                else { completion(.success(())) }
            }
        }
    }

    // MARK: - Link-joinable invites & manual join (1.2.52)

    /// Promote a share to "anyone with the link can join (and edit)" BEFORE its
    /// raw URL is sent through LINE / mail. The custom invite message promises
    /// exactly that; with the previous invite-only default, recipients opening
    /// the link were asked to sign in to their Apple Account and then hit a
    /// dead end, because their Apple ID was never an invited participant.
    /// Completion runs on the main thread.
    func ensureLinkJoinable(_ share: CKShare, completion: @escaping (Result<Void, Error>) -> Void) {
        guard share.publicPermission == .none else {
            completion(.success(())); return
        }
        guard let store = persistence.privateStore else {
            completion(.failure(AppError.shareCreationFailed(NSLocalizedString("共有ストアが利用できません。", comment: ""))))
            return
        }
        share.publicPermission = .readWrite
        persistence.container.persistUpdatedShare(share, in: store) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let error else { completion(.success(())); return }
                // The server refuses to make a share public while UNCLAIMED
                // email-invite participants are attached — a real-device
                // failure: CKInternalErrorDomain #2043 "Unclaimed one time
                // link participant can only be user". Those pending entries
                // are relics of invite-only sharing (≤1.2.1); the people
                // behind them never joined and can join via the new public
                // link anyway — so drop them and retry ONCE.
                let pending = share.participants.filter { $0.role != .owner && $0.acceptanceStatus == .pending }
                guard !pending.isEmpty else { completion(.failure(error)); return }
                pending.forEach { share.removeParticipant($0) }
                share.publicPermission = .readWrite
                self.persistence.container.persistUpdatedShare(share, in: store) { _, retryError in
                    DispatchQueue.main.async {
                        if let retryError { completion(.failure(retryError)) } else { completion(.success(())) }
                    }
                }
            }
        }
    }

    /// Accept an invitation from a pasted share URL. This is the recovery path
    /// when the link was opened in an in-app browser (LINE など) that cannot
    /// hand the invitation to the app: the user copies the link and joins here.
    /// Completion runs on the main thread.
    func joinShare(from url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        guard persistence.cloudKitEnabled else {
            completion(.failure(AppError.shareCreationFailed(NSLocalizedString("このビルドでは共有を利用できません。", comment: ""))))
            return
        }
        let operation = CKFetchShareMetadataOperation(shareURLs: [url])
        var fetched: Result<CKShare.Metadata, Error>?
        operation.perShareMetadataResultBlock = { _, result in fetched = result }
        operation.fetchShareMetadataResultBlock = { [weak self] overall in
            DispatchQueue.main.async {
                guard let self else { return }
                switch fetched {
                case .success(let metadata):
                    self.acceptShare(metadata: metadata) { result in
                        completion(result.mapError { Self.friendlyJoinError($0) })
                    }
                case .failure(let error):
                    completion(.failure(Self.friendlyJoinError(error)))
                case nil:
                    if case .failure(let error) = overall {
                        completion(.failure(Self.friendlyJoinError(error)))
                    } else {
                        completion(.failure(AppError.shareCreationFailed(
                            NSLocalizedString("招待リンクを確認できませんでした。リンクが正しいかご確認ください。", comment: ""))))
                    }
                }
            }
        }
        operation.qualityOfService = .userInitiated
        ckContainer.add(operation)
    }

    /// Map raw CloudKit join failures to actionable guidance. The big one is
    /// backwards compatibility: links created by ≤1.2.1 are invite-only, so a
    /// pasted link fails verification for anyone who wasn't explicitly added —
    /// the fix is a re-sent link from an updated app, and the message says so.
    static func friendlyJoinError(_ error: Error) -> Error {
        guard let ck = error as? CKError else { return error }
        switch ck.code {
        case .participantMayNeedVerification, .permissionFailure:
            return AppError.shareCreationFailed(NSLocalizedString(
                "この招待リンクは「招待した人のみ」の設定で作られています。送った人にタナミルを最新版に更新してもらい、「招待リンクを送る」からリンクを送り直してもらってください。", comment: ""))
        case .networkUnavailable, .networkFailure:
            return AppError.shareCreationFailed(NSLocalizedString(
                "ネットワークに接続できません。電波の良い場所でもう一度お試しください。", comment: ""))
        case .unknownItem:
            return AppError.shareCreationFailed(NSLocalizedString(
                "この招待リンクは使えなくなっています（共有が停止された可能性があります）。送った人に新しいリンクをもらってください。", comment: ""))
        case .notAuthenticated:
            return AppError.shareCreationFailed(NSLocalizedString(
                "iCloudにサインインしていないため参加できません。設定アプリでiCloudにサインインしてから、もう一度お試しください。", comment: ""))
        default:
            return error
        }
    }

    /// Pull the iCloud share URL out of arbitrary pasted text (users often copy
    /// the whole invite message, not just the link).
    static func extractShareURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate: String
        if let range = trimmed.range(of: #"https://www\.icloud\.com/share/[^\s]+"#, options: .regularExpression) {
            candidate = String(trimmed[range])
        } else if trimmed.lowercased().hasPrefix("https://"), trimmed.contains("icloud.com") {
            candidate = trimmed
        } else {
            return nil
        }
        if let url = URL(string: candidate), url.host?.hasSuffix("icloud.com") == true { return url }
        // A hand-copied fragment (#プロジェクト名) may be un-encoded and break
        // URL(string:); the share token before '#' is all the server needs.
        if let base = candidate.split(separator: "#").first,
           let url = URL(string: String(base)), url.host?.hasSuffix("icloud.com") == true { return url }
        return nil
    }
}
