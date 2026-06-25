import Foundation

/// Central place to read build-time configuration that comes from
/// `Config.xcconfig` → Info.plist substitution. Keeping these lookups in one
/// type means the rest of the app never hard-codes a bundle / container id.
enum AppConfig {

    /// CloudKit container identifier (e.g. `iCloud.com.example.projectstock`).
    /// Sourced from Info.plist key `CloudKitContainerIdentifier`, which is set
    /// to `$(CLOUDKIT_CONTAINER_IDENTIFIER)` in the build settings.
    static var cloudKitContainerIdentifier: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CloudKitContainerIdentifier") as? String
        if let value, !value.isEmpty, value != "$(CLOUDKIT_CONTAINER_IDENTIFIER)" {
            return value
        }
        // Fallback derives a container id from the bundle id so debug builds
        // without a filled-in xcconfig still construct *something* valid.
        return "iCloud." + (Bundle.main.bundleIdentifier ?? "com.example.projectstock")
    }

    static var displayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "ProjectStock"
    }

    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// `true` when running inside an automated test / UI-test run. We disable
    /// CloudKit and seed deterministic state in that case.
    static var isRunningTests: Bool {
        if NSClassFromString("XCTestCase") != nil { return true }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        return ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }

    /// UI tests pass `-uiTesting` to route the scanner through a mock and to
    /// start from a clean store.
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }
}
