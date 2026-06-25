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
                    completion(.failure(error)); return
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

    /// Accept an incoming share invitation into the SHARED store.
    func acceptShare(metadata: CKShare.Metadata, completion: @escaping (Result<Void, Error>) -> Void) {
        guard persistence.cloudKitEnabled, let sharedStore = persistence.sharedStore else {
            completion(.failure(AppError.shareCreationFailed(NSLocalizedString("共有ストアが利用できません。", comment: ""))))
            return
        }
        persistence.container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, _, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)) }
                else { completion(.success(())) }
            }
        }
    }
}
