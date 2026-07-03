import SwiftUI
import CloudKit
import CoreData
import UIKit
import ObjectiveC

/// Presents `UICloudSharingController` DIRECTLY through UIKit rather than wrapping
/// it in a SwiftUI `.sheet` (spec §10).
///
/// Why not `.sheet`: the share section observes `CloudKitSyncMonitor`, which
/// publishes on every CloudKit import/export event. While sync is active (or in
/// an error/retry loop) those events fire constantly, re-rendering the section —
/// and a `.sheet`-hosted `UIViewControllerRepresentable` gets torn down and
/// re-presented on that re-render, so the share sheet "flashes open then closes"
/// on the first tap and only survives a later tap that happens not to collide
/// with an event. Presenting the controller straight from the key window's top
/// view controller makes it immune to SwiftUI re-renders entirely.
///
/// Initializer choice (unchanged, and correct):
///  * NOT yet shared → `init(preparationHandler:)`, creating the CKShare INSIDE
///    the handler via `NSPersistentCloudKitContainer.share(_:to:)`.
///  * ALREADY shared → `init(share:container:)`.
/// After a save, `persistUpdatedShare(_:in:)` writes the share back into the
/// private store (Core Data does not do this automatically).
enum CloudSharePresenter {

    static func present(persistence: PersistenceController,
                        objectID: NSManagedObjectID,
                        title: String,
                        existingShare: CKShare?,
                        syncMonitor: CloudKitSyncMonitor,
                        onSaved: @escaping () -> Void = {},
                        onStopSharing: @escaping () -> Void = {},
                        onError: @escaping (Error) -> Void = { _ in }) {
        guard let top = topViewController() else {
            onError(AppError.shareCreationFailed(
                NSLocalizedString("共有画面を表示できませんでした。もう一度お試しください。", comment: "")))
            return
        }

        let ckContainer = CKContainer(identifier: AppConfig.cloudKitContainerIdentifier)
        let controller: UICloudSharingController
        if let existingShare {
            controller = UICloudSharingController(share: existingShare, container: ckContainer)
        } else {
            controller = UICloudSharingController { _, completion in
                let context = persistence.viewContext
                guard let object = try? context.existingObject(with: objectID) else {
                    completion(nil, nil, AppError.shareCreationFailed(
                        NSLocalizedString("共有する対象が見つかりませんでした。", comment: "")))
                    return
                }
                persistence.container.share([object], to: nil) { _, share, container, error in
                    if let share {
                        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
                    }
                    completion(share, container, error)
                }
            }
        }

        let coordinator = Coordinator(persistence: persistence, title: title,
                                      syncMonitor: syncMonitor,
                                      onSaved: onSaved, onStopSharing: onStopSharing, onError: onError)
        controller.delegate = coordinator
        // `delegate` is weak — keep the coordinator alive exactly as long as the
        // controller by hanging it off the controller as an associated object.
        objc_setAssociatedObject(controller, &Coordinator.associationKey, coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        controller.availablePermissions = [.allowReadWrite, .allowReadOnly, .allowPrivate]

        // iPad requires a popover anchor or it traps.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        syncMonitor.logShareEvent(existingShare == nil
            ? NSLocalizedString("共有シートを開きます（新規作成）", comment: "")
            : NSLocalizedString("共有シートを開きます（既存の共有を管理）", comment: ""))
        top.present(controller, animated: true)
    }

    /// The front-most presented view controller of the active key window.
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            ?? scenes.compactMap { $0 as? UIWindowScene }.first
        guard let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first else { return nil }
        var top = window.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        static var associationKey: UInt8 = 0
        let persistence: PersistenceController
        let title: String
        let syncMonitor: CloudKitSyncMonitor
        let onSaved: () -> Void
        let onStopSharing: () -> Void
        let onError: (Error) -> Void

        init(persistence: PersistenceController, title: String, syncMonitor: CloudKitSyncMonitor,
             onSaved: @escaping () -> Void, onStopSharing: @escaping () -> Void, onError: @escaping (Error) -> Void) {
            self.persistence = persistence
            self.title = title
            self.syncMonitor = syncMonitor
            self.onSaved = onSaved
            self.onStopSharing = onStopSharing
            self.onError = onError
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            syncMonitor.logShareEvent(NSLocalizedString("共有に失敗しました", comment: ""), error: error)
            onError(error)
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            if let share = csc.share, let store = persistence.privateStore {
                persistence.container.persistUpdatedShare(share, in: store) { [weak self] _, error in
                    if let error = error {
                        self?.syncMonitor.logShareEvent(NSLocalizedString("共有の保存後処理に失敗", comment: ""), error: error)
                        self?.onError(error)
                    }
                }
            }
            syncMonitor.logShareEvent(NSLocalizedString("共有を保存しました", comment: ""))
            onSaved()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            syncMonitor.logShareEvent(NSLocalizedString("共有を停止しました", comment: ""))
            onStopSharing()
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? { nil }
    }
}
