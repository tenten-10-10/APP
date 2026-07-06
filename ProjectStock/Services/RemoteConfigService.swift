import Foundation
import Combine

/// Remote feature flags / kill-switches / notices, fetched from the marketing
/// site: https://tanamiru.l0l0.app/app-config.json. The file lives in this
/// repo (tanamiru-site/app-config.json) and deploys automatically on push, so
/// app behavior can be adjusted within a minute WITHOUT an App Store release —
/// e.g. turning the チーム共有プラン on once the ASC products exist, or
/// disabling a risky feature if a data-loss bug is discovered in the field.
///
/// Design rules:
///  * The app must behave sensibly with no network at all: every read has a
///    hard-coded default, and the last good config is cached in UserDefaults.
///  * Config only toggles behavior that already shipped (feature flags and
///    notices). It never downloads code or changes prices — both would
///    violate App Review guidelines.
///
/// Current keys (see docs/DEV_NOTES_JA.md §10):
///  * v                : Int, schema version — payload ignored unless present.
///  * teamPlanEnabled  : Bool, shows the チーム paywall gate + Settings row.
///  * deleteEnabled    : Bool, kill-switch for product/unit deletion UI.
///  * sharingEnabled   : Bool, kill-switch for STARTING new CloudKit shares.
///  * notice           : {title?, message, url?} — banner on the Home screen.
@MainActor
final class RemoteConfig: ObservableObject {

    static let shared = RemoteConfig()

    static let configURL = URL(string: "https://tanamiru.l0l0.app/app-config.json")!
    private static let cacheKey = "remoteConfigCache"
    private static let refreshInterval: TimeInterval = 15 * 60

    @Published private(set) var raw: [String: Any] = [:]
    private var lastFetch: Date?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            raw = json
        }
    }

    // MARK: - Typed reads (always with a safe default)

    func bool(_ key: String, default defaultValue: Bool) -> Bool {
        raw[key] as? Bool ?? defaultValue
    }

    func string(_ key: String) -> String? {
        raw[key] as? String
    }

    /// お知らせバナー。未配信のときは nil。
    var notice: Notice? {
        guard let dict = raw["notice"] as? [String: Any],
              let message = dict["message"] as? String, !message.isEmpty else { return nil }
        return Notice(title: dict["title"] as? String,
                      message: message,
                      url: (dict["url"] as? String).flatMap(URL.init(string:)))
    }

    struct Notice: Equatable {
        let title: String?
        let message: String
        let url: URL?
    }

    // MARK: - Fetch

    /// Fetch the latest config. Throttled to one request per 15 minutes unless
    /// `force` — safe to call on every launch and foreground transition.
    /// Failures (offline, site down, malformed JSON) keep the cached values.
    func refresh(force: Bool = false) async {
        if !force, let last = lastFetch, Date().timeIntervalSince(last) < Self.refreshInterval { return }
        lastFetch = Date()
        var request = URLRequest(url: Self.configURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = (try JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  json["v"] is Int else { return }
            raw = json
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        } catch {
            // Keep last-good values; the hard-coded defaults cover first launch.
        }
    }
}
