import Foundation
import CoreData
#if canImport(UserNotifications)
import UserNotifications
#endif

/// A primitive snapshot of a loan's notification, safe to pass across threads
/// (it holds no managed objects).
struct LoanNotice {
    let identifier: String
    let title: String
    let body: String
    let due: Date
}

/// Schedules local notifications for loan due-dates and lot expiry.
/// Each loan/lot maps to at most one pending notification, keyed by the unit
/// id, so re-syncing is idempotent.
///
/// All public methods operate on value types (`LoanNotice`) or plain strings so
/// they can be called from any thread — managed objects are converted to
/// `LoanNotice` on their own context queue by the caller.
///
/// IMPORTANT: Loan and expiry notifications use distinct identifier prefixes
/// ("loan-" and "expiry-"). Each `sync` call only removes stale notifications
/// whose identifier starts with the supplied prefix, ensuring the two sets
/// never clobber each other.
final class NotificationService {

    static let shared = NotificationService()

    // MARK: - Identifier prefixes (one per domain)

    private static let loanPrefix   = "loan-"
    private static let expiryPrefix = "expiry-"

    static func loanIdentifier(unitID: UUID)   -> String { loanPrefix   + unitID.uuidString }
    static func expiryIdentifier(unitID: UUID) -> String { expiryPrefix + unitID.uuidString }

    /// Notifications are pointless (and the API is unavailable) during tests.
    private var isAvailable: Bool { !AppConfig.isRunningTests }

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        guard isAvailable else { completion?(false); return }
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion?(granted) }
        }
        #else
        completion?(false)
        #endif
    }

    // MARK: - Loan notifications

    /// Reconcile the set of pending loan notifications with `notices`: schedule
    /// each future notice and remove any stale *loan* notification (returned or
    /// corrected loans). Past-due notices are not scheduled — the UI surfaces
    /// those as overdue badges instead.
    /// Only identifiers with prefix "loan-" are touched; expiry notifications
    /// are left completely unchanged.
    func sync(notices: [LoanNotice]) {
        syncNotices(notices, prefix: Self.loanPrefix)
    }

    // MARK: - Expiry notifications

    /// Reconcile pending lot-expiry notifications with `notices`.
    /// Only identifiers with prefix "expiry-" are touched; loan notifications
    /// are left completely unchanged.
    func syncExpiry(notices: [LoanNotice]) {
        syncNotices(notices, prefix: Self.expiryPrefix)
    }

    // MARK: - Shared sync implementation

    /// Generic sync scoped to a single prefix: schedules future notices and
    /// removes stale pending notifications whose identifier starts with
    /// `prefix` and is not in the new `notices` set.
    private func syncNotices(_ notices: [LoanNotice], prefix: String) {
        guard isAvailable else { return }
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let now = Date()
        let future = notices.filter { $0.due > now }
        let wanted = Set(future.map(\.identifier))
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier)
                .filter { $0.hasPrefix(prefix) && !wanted.contains($0) }
            if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
            for notice in future { center.add(Self.makeRequest(notice)) }
        }
        #endif
    }

    // MARK: - Cancel single

    func cancel(identifier: String) {
        guard isAvailable else { return }
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        #endif
    }

    // MARK: - Request builder

    #if canImport(UserNotifications)
    private static func makeRequest(_ notice: LoanNotice) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notice.due)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: notice.identifier, content: content, trigger: trigger)
    }
    #endif
}
