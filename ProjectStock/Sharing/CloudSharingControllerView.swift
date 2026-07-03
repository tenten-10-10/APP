import SwiftUI
import CloudKit
import CoreData
import UIKit

/// SwiftUI wrapper around `UICloudSharingController` (spec §10), using the
/// initializer Apple actually requires:
///
///  * Project NOT yet shared → `init(preparationHandler:)`. The CKShare is
///    created INSIDE the handler via `NSPersistentCloudKitContainer.share(_:to:)`
///    and we only call the controller's completion once Core Data has scheduled
///    the export — so the controller uploads the share/records itself before the
///    invite step. (Passing a freshly-created share to `init(share:container:)`
///    is explicitly warned against by Apple and is what produced
///    `failedToSaveShareWithError` = 「共有するためのリンクを作成できませんでした」.)
///  * Project ALREADY shared → `init(share:container:)`.
///
/// After the controller saves, `persistUpdatedShare(_:in:)` writes the share
/// back into the private store — Core Data does NOT do this automatically for
/// changes `UICloudSharingController` makes.
struct CloudSharingControllerView: UIViewControllerRepresentable {

    let persistence: PersistenceController
    let objectID: NSManagedObjectID
    let title: String
    let existingShare: CKShare?
    var onSaved: () -> Void = {}
    var onStopSharing: () -> Void = {}
    var onError: (Error) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let ckContainer = CKContainer(identifier: AppConfig.cloudKitContainerIdentifier)
        let controller: UICloudSharingController

        if let existingShare {
            controller = UICloudSharingController(share: existingShare, container: ckContainer)
        } else {
            let persistence = self.persistence
            let objectID = self.objectID
            let title = self.title
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

        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite, .allowReadOnly, .allowPrivate]
        controller.modalPresentationStyle = .formSheet
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let parent: CloudSharingControllerView
        init(_ parent: CloudSharingControllerView) { self.parent = parent }

        func itemTitle(for csc: UICloudSharingController) -> String? { parent.title }

        func cloudSharingController(_ csc: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) {
            parent.onError(error)
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            if let share = csc.share, let store = parent.persistence.privateStore {
                parent.persistence.container.persistUpdatedShare(share, in: store) { [weak self] _, error in
                    if let error = error { self?.parent.onError(error) }
                }
            }
            parent.onSaved()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            parent.onStopSharing()
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? { nil }
    }
}
