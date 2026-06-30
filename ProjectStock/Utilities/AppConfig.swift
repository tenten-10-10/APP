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
            ?? "タナミル"
    }

    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    /// Apple's numeric App Store id for タナミル. Used to build an install link
    /// (e.g. inside a CloudKit share invitation, so an invited colleague who
    /// doesn't have the app yet can get it from the App Store first).
    static let appStoreID = "6784470155"

    /// Public App Store product URL for タナミル.
    static var appStoreURL: String { "https://apps.apple.com/app/id\(appStoreID)" }

    /// Host for QR Universal Links. Labels encode `https://<linkHost>/<code>` so
    /// an iPhone WITHOUT タナミル can scan with the Camera app and be sent to the
    /// App Store, while an installed app opens straight to that item.
    static let linkHost = "t.l0l0.app"

    /// The string actually encoded into a QR label for a given public code.
    static func qrPayload(for code: String) -> String { "https://\(linkHost)/\(code)" }

    /// Extract a public code from a raw scanned value or opened URL. Accepts a
    /// bare code (old labels) and a Universal Link URL (new labels / deep links).
    static func extractCode(fromScanned raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           let host = url.host?.lowercased(),
           host == linkHost || host == "www.\(linkHost)",
           let last = url.pathComponents.last(where: { $0 != "/" && !$0.isEmpty }) {
            return last
        }
        return trimmed
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

    /// App Store screenshot runs pass `-snapshotData` (alongside `-uiTesting`)
    /// to seed a populated demo project so captures look representative.
    static var isSnapshot: Bool {
        ProcessInfo.processInfo.arguments.contains("-snapshotData")
    }
}
