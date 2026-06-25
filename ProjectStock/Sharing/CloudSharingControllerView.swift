import SwiftUI
import CloudKit
import UIKit

/// SwiftUI wrapper around `UICloudSharingController` (spec §10). Present it in a
/// `.sheet`; it supports read-only / read-write permissions and reports
/// stop-sharing / participation changes back through closures.
struct CloudSharingControllerView: UIViewControllerRepresentable {

    let share: CKShare
    let container: CKContainer
    let title: String
    var onSaved: () -> Void = {}
    var onStopSharing: () -> Void = {}
    var onError: (Error) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
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
            parent.onSaved()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            parent.onStopSharing()
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? { nil }
    }
}
