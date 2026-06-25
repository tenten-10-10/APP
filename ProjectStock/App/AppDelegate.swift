import UIKit
import CloudKit

/// Notification used to forward a CloudKit share invitation from the
/// UIKit-level acceptance callback to the SwiftUI service layer (spec §10).
extension Notification.Name {
    static let projectStockDidReceiveShareMetadata = Notification.Name("ProjectStock.didReceiveShareMetadata")
}

enum ShareAcceptanceKeys {
    static let metadata = "metadata"
}

/// Minimal app delegate. Its sole job beyond launch is to receive CloudKit
/// share invitations and hand the metadata to the service layer, which accepts
/// them into the shared store. SwiftUI's `App` still owns the window.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        true
    }

    // Called when the user taps a share link while the app is the handler.
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        NotificationCenter.default.post(name: .projectStockDidReceiveShareMetadata,
                                        object: nil,
                                        userInfo: [ShareAcceptanceKeys.metadata: cloudKitShareMetadata])
    }

    // Route every scene through our scene delegate so the scene-level share
    // callback is also delivered, without taking over window creation.
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = ShareSceneDelegate.self
        return config
    }
}

/// Scene delegate that ONLY forwards the share-acceptance callback. It does not
/// implement `scene(_:willConnectTo:)`, so SwiftUI continues to build the UI.
final class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        NotificationCenter.default.post(name: .projectStockDidReceiveShareMetadata,
                                        object: nil,
                                        userInfo: [ShareAcceptanceKeys.metadata: cloudKitShareMetadata])
    }
}
