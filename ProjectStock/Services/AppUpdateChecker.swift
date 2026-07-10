import Foundation

/// Checks the App Store for a newer *published* version than the one installed,
/// so Home can show a persistent "アップデートがあります" banner. Uses Apple's
/// public iTunes Lookup endpoint (no auth, no SDK); any failure just leaves the
/// banner hidden — it never blocks or errors in the UI.
///
/// Note: the App Store lookup can lag a few hours behind an actual release, so
/// the banner may appear a little AFTER a version goes live. That's expected and
/// fine — the point is a durable nudge, not an instant one.
@MainActor
final class AppUpdateChecker: ObservableObject {

    static let shared = AppUpdateChecker()

    /// The App Store version string when it is strictly NEWER than the installed
    /// build; `nil` when up to date or the check hasn't succeeded.
    @Published private(set) var availableVersion: String?

    private var lastCheck: Date?
    private let minInterval: TimeInterval = 60 * 60   // at most once per hour
    private let session: URLSession

    private init(session: URLSession = .shared) { self.session = session }

    /// The running app's marketing version (CFBundleShortVersionString).
    var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Deep link to open the App Store product page for the update.
    var appStoreURL: URL? { URL(string: AppConfig.appStoreURL) }

    /// Query the App Store. `force` bypasses the once-per-hour throttle.
    func check(force: Bool = false) async {
        if AppConfig.isRunningTests { return }
        if !force, let last = lastCheck, Date().timeIntervalSince(last) < minInterval { return }
        guard let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty else { return }
        var comps = URLComponents(string: "https://itunes.apple.com/lookup")
        comps?.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleId),
            URLQueryItem(name: "country", value: "jp")
        ]
        guard let url = comps?.url else { return }
        var request = URLRequest(url: url)
        // The App Store version changes over time — don't serve a stale cache.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        do {
            let (data, _) = try await session.data(for: request)
            lastCheck = Date()
            if let store = Self.storeVersion(from: data),
               Self.isNewer(store, than: installedVersion) {
                availableVersion = store
            } else {
                availableVersion = nil
            }
        } catch {
            // Silent — a failed check simply keeps the banner hidden.
        }
    }

    /// Parse the App Store version out of an iTunes Lookup response.
    nonisolated static func storeVersion(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let version = results.first?["version"] as? String else { return nil }
        return version
    }

    /// True when dotted-numeric `a` (e.g. "1.2.63") is strictly newer than `b`
    /// ("1.2.7"). Compares component-by-component numerically so "1.2.10" > "1.2.9".
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
