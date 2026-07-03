import Foundation

/// Launch-time crash protection & diagnosis.
///
/// Two jobs:
///  1. Record the reason of an uncaught Obj-C exception (e.g. a Core Data fetch
///     that throws during the first SwiftUI render). TestFlight/App Store crash
///     logs strip the NSException `reason`, so we capture it ourselves — it's
///     the only way to see WHY a launch-time Core Data crash happened.
///  2. Detect a launch crash-loop and fall back to **safe mode** (CloudKit sync
///     disabled) so the app always opens locally instead of crashing forever.
///
/// Flow: `beginLaunch()` runs first thing in `App.init`. It reads a counter that
/// the previous launch left incremented; if the previous launch never reached a
/// stable state (`markStable()` was never called — i.e. it crashed), this launch
/// starts in safe mode. Once the app has been up for a few seconds without
/// crashing, `markStable()` resets the counter so the next launch tries sync again.
enum LaunchCrashGuard {

    private static let counterKey = "launch.unstableCount"
    private static let exceptionKey = "launch.lastException"
    private static let defaults = UserDefaults.standard

    /// True when this launch disabled CloudKit because the previous launch
    /// crashed before becoming stable.
    private(set) static var safeModeActive = false

    /// The reason string of the last uncaught exception, if any.
    static var lastException: String? {
        let value = defaults.string(forKey: exceptionKey)
        return (value?.isEmpty == false) ? value : nil
    }

    /// Call once, as the very first thing in `App.init`.
    static func beginLaunch() {
        NSSetUncaughtExceptionHandler { exception in
            let name = exception.name.rawValue
            let reason = exception.reason ?? ""
            let text = "\(name): \(reason)"
            let ud = UserDefaults.standard
            ud.set(text, forKey: exceptionKey)
            ud.synchronize()
        }

        let previous = defaults.integer(forKey: counterKey)
        // >= 1 means the previous launch incremented the counter but never
        // reached markStable() — it crashed during launch.
        safeModeActive = previous >= 1
        defaults.set(previous + 1, forKey: counterKey)
        defaults.synchronize()
    }

    /// Call once the app has rendered and run for a few seconds without crashing.
    static func markStable() {
        defaults.set(0, forKey: counterKey)
        defaults.synchronize()
    }

    /// User acknowledged the recorded crash — stop showing it.
    static func clearRecordedException() {
        defaults.removeObject(forKey: exceptionKey)
        defaults.synchronize()
    }

    /// Let the user re-enable sync on the next launch after we (hopefully) ship
    /// a fix — clears both the loop counter and the recorded exception.
    static func resetForRetry() {
        defaults.set(0, forKey: counterKey)
        defaults.removeObject(forKey: exceptionKey)
        defaults.synchronize()
    }
}
