import Foundation
import CoreData
import CloudKit
import Combine
import os.log

/// User-facing sync state (spec §13). Deliberately avoids exposing a
/// misleading "sync now" control — CloudKit decides when to push/pull. We just
/// report status, retryability, and diagnostics.
enum SyncState: Equatable {
    case localOnly          // iCloud not configured / CloudKit disabled
    case synced
    case syncing
    case pendingUpload
    case offline
    case error(String)

    var isError: Bool { if case .error = self { return true }; return false }

    var localizedTitle: String {
        switch self {
        case .localOnly:     return NSLocalizedString("ローカルのみ", comment: "")
        case .synced:        return NSLocalizedString("同期済み", comment: "")
        case .syncing:       return NSLocalizedString("同期中", comment: "")
        case .pendingUpload: return NSLocalizedString("アップロード待ち", comment: "")
        case .offline:       return NSLocalizedString("オフライン", comment: "")
        case .error:         return NSLocalizedString("同期エラー", comment: "")
        }
    }

    var systemImageName: String {
        switch self {
        case .localOnly:     return "icloud.slash"
        case .synced:        return "checkmark.icloud"
        case .syncing:       return "arrow.triangle.2.circlepath.icloud"
        case .pendingUpload: return "icloud.and.arrow.up"
        case .offline:       return "wifi.slash"
        case .error:         return "exclamationmark.icloud"
        }
    }
}

/// iCloud account availability mapped to friendly guidance (spec §14).
enum AccountState: Equatable {
    case available
    case noAccount          // not signed in to iCloud
    case restricted         // parental controls / MDM
    case temporarilyUnavailable
    case couldNotDetermine
    case cloudKitDisabled   // build without CloudKit

    var localizedMessage: String {
        switch self {
        case .available:
            return NSLocalizedString("iCloudに接続済みです。", comment: "")
        case .noAccount:
            return NSLocalizedString("iCloudにサインインすると、データのバックアップとチーム共有が使えます。設定アプリからサインインしてください。", comment: "")
        case .restricted:
            return NSLocalizedString("この端末ではiCloudの利用が制限されています。", comment: "")
        case .temporarilyUnavailable:
            return NSLocalizedString("iCloudアカウントが一時的に利用できません。しばらくして再度お試しください。", comment: "")
        case .couldNotDetermine:
            return NSLocalizedString("iCloudの状態を確認できませんでした。ネットワークを確認してください。", comment: "")
        case .cloudKitDisabled:
            return NSLocalizedString("このビルドではiCloud同期は無効です。データはこの端末にのみ保存されます。", comment: "")
        }
    }
}

/// Observes Core Data + CloudKit notifications and exposes a single observable
/// status the UI can subscribe to. All `@Published` mutations are funnelled to
/// the main thread internally so views can observe it directly.
final class CloudKitSyncMonitor: ObservableObject {

    @Published private(set) var syncState: SyncState
    @Published private(set) var accountState: AccountState = .couldNotDetermine
    /// Rolling log of import/export events, newest first, for the diagnostics UI.
    @Published private(set) var recentEvents: [SyncLogEntry] = []

    private let persistence: PersistenceController
    private let logger = Logger(subsystem: "ProjectStock", category: "CloudKitSync")
    private var cancellables = Set<AnyCancellable>()
    private var inFlightSetup = false
    private var inFlightImport = false
    private var inFlightExport = false
    /// How many sync events in a row have failed. CloudKit routinely fails a
    /// single export/import transiently (rate limit, busy zone, brief network
    /// blip) and then retries successfully — flashing a red 同期エラー badge for
    /// each of those scares users for nothing. We only surface an error state
    /// once failures PERSIST (see `errorDisplayThreshold`) or the error is
    /// definitive (sign-in / quota / permission), while every failure is still
    /// recorded in the diagnostics log.
    private var consecutiveFailures = 0
    private let errorDisplayThreshold = 3
    /// CloudKit fires import/export events in bursts — batched delta sync, one
    /// per store (private + shared), plus it re-imports its own exports. Logging
    /// every routine "完了" floods the diagnostics feed (dozens per minute) and
    /// buries the entries that matter (errors, 共有 milestones). We therefore log
    /// at most one routine success per `routineSuccessLogInterval`; the live sync
    /// badge still updates every event, and failures are never throttled.
    private var lastRoutineSuccessLoggedAt: Date?
    private let routineSuccessLogInterval: TimeInterval = 30

    init(persistence: PersistenceController) {
        self.persistence = persistence
        self.syncState = persistence.cloudKitEnabled ? .syncing : .localOnly
        guard persistence.cloudKitEnabled else {
            self.accountState = .cloudKitDisabled
            return
        }
        observeCloudKitEvents()
        refreshAccountStatus()

        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recomputeState() }
            .store(in: &cancellables)
    }

    private func observeCloudKitEvents() {
        NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in self?.handleEvent(note) }
            .store(in: &cancellables)
    }

    private func handleEvent(_ note: Notification) {
        guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }

        let isStart = event.endDate == nil
        switch event.type {
        case .setup:  inFlightSetup = isStart
        case .import: inFlightImport = isStart
        case .export: inFlightExport = isStart
        @unknown default: break
        }

        if let error = event.error {
            let mapped = CloudKitErrorMapper.userMessage(for: error)
            // Record the SPECIFIC per-record reason in the diagnostics log (the
            // status badge stays friendly). The short per-record summary pinpoints
            // e.g. a Production schema missing/mismatched field; the full tree
            // dump is the safety net that surfaces whatever hidden userInfo key
            // holds the real server reason this time.
            let detail = CloudKitErrorMapper.partialFailureDetail(for: error)
            let full = CloudKitErrorMapper.fullDiagnosticDump(for: error)
            let logMessage = [mapped, detail, full]
                .compactMap { $0 }
                .joined(separator: "\n")
            log(SyncLogEntry(type: event.type, succeeded: false, message: logMessage))
            // Let the next success log immediately so a recovery is visible even
            // if it lands within the throttle window.
            lastRoutineSuccessLoggedAt = nil
            consecutiveFailures += 1
            if isDefinitiveFailure(error) || consecutiveFailures >= errorDisplayThreshold {
                syncState = .error(mapped)
            } else if !syncState.isError {
                // Transient one-off failure: CloudKit will retry on its own.
                // Keep the badge calm instead of flashing 同期エラー.
                syncState = .syncing
            }
            mapAccountError(error)
        } else if !isStart {
            // Throttle routine successes so a sync burst collapses to ~1 log line
            // instead of dozens. Only the log entry is throttled — the state
            // release + recompute below still run for every completed event.
            let now = Date()
            if lastRoutineSuccessLoggedAt.map({ now.timeIntervalSince($0) >= routineSuccessLogInterval }) ?? true {
                lastRoutineSuccessLoggedAt = now
                log(SyncLogEntry(type: event.type, succeeded: true, message: NSLocalizedString("完了", comment: "")))
            }
            consecutiveFailures = 0
            // A completed import/export means CloudKit is talking to the server
            // again — release a sticky error HERE, because recomputeState()
            // deliberately holds `.error` and would return without clearing it.
            // Without this, one failed export at launch (e.g. the pending-share
            // batch) pinned the badge on 同期エラー forever and the user had to
            // tap 再確認 manually every single time they opened the app.
            if syncState.isError { syncState = .syncing }
            recomputeState()
        } else {
            recomputeState()
        }
    }

    private func recomputeState() {
        guard persistence.cloudKitEnabled else { syncState = .localOnly; return }
        if case .error = syncState { return } // hold error until next success
        if inFlightSetup || inFlightImport || inFlightExport {
            syncState = .syncing
        } else if accountState == .noAccount {
            syncState = .localOnly
        } else if accountState == .temporarilyUnavailable || accountState == .couldNotDetermine {
            syncState = .offline
        } else {
            syncState = .synced
        }
    }

    func refreshAccountStatus() {
        guard persistence.cloudKitEnabled else { accountState = .cloudKitDisabled; return }
        let container = CKContainer(identifier: AppConfig.cloudKitContainerIdentifier)
        container.accountStatus { [weak self] status, error in
            Task { @MainActor in
                guard let self else { return }
                if error != nil { self.accountState = .couldNotDetermine }
                else {
                    switch status {
                    case .available:            self.accountState = .available
                    case .noAccount:            self.accountState = .noAccount
                    case .restricted:           self.accountState = .restricted
                    case .temporarilyUnavailable: self.accountState = .temporarilyUnavailable
                    case .couldNotDetermine:    self.accountState = .couldNotDetermine
                    @unknown default:           self.accountState = .couldNotDetermine
                    }
                }
                self.recomputeState()
            }
        }
    }

    /// Record a share-flow milestone (start / prepared / saved / failed) into the
    /// SAME diagnostics feed the user copies from 設定 > 診断. The UICloudSharingController
    /// delegate reports its own errors OUT of band from CloudKit's export events,
    /// so without this a failed share leaves no trace in diagnostics and we're
    /// blind to WHY it failed. `error`, if present, is dumped in full.
    func logShareEvent(_ message: String, error: Error? = nil) {
        let full = error.flatMap { CloudKitErrorMapper.fullDiagnosticDump(for: $0) }
        let composed = full.map { "\(message)\n\($0)" } ?? message
        log(SyncLogEntry(type: .export, succeeded: error == nil, message: "[共有] \(composed)"))
    }

    /// Clear a sticky error so the UI can re-evaluate after a retry.
    func clearError() {
        consecutiveFailures = 0
        if syncState.isError { syncState = .syncing; recomputeState() }
        refreshAccountStatus()
    }

    /// Errors that will NOT fix themselves via CloudKit's automatic retry —
    /// show these immediately instead of waiting for the failure streak.
    private func isDefinitiveFailure(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        switch ckError.code {
        case .notAuthenticated, .quotaExceeded, .permissionFailure,
             .managedAccountRestricted, .missingEntitlement, .badContainer:
            return true
        default:
            return false
        }
    }

    private func mapAccountError(_ error: Error) {
        guard let ckError = error as? CKError else { return }
        switch ckError.code {
        case .notAuthenticated:        accountState = .noAccount
        case .accountTemporarilyUnavailable: accountState = .temporarilyUnavailable
        case .networkUnavailable, .networkFailure: syncState = .offline
        default: break
        }
    }

    private func log(_ entry: SyncLogEntry) {
        // MUST hop to main: `logShareEvent` is called from CloudKit/CoreData
        // completion queues (e.g. persistUpdatedShare), and mutating a
        // @Published array off the main thread crashes SwiftUI's render graph
        // (EXC_BREAKPOINT in AttributeGraph — proven by a 1.2.51 field crash).
        if Thread.isMainThread {
            applyLog(entry)
        } else {
            DispatchQueue.main.async { self.applyLog(entry) }
        }
    }

    private func applyLog(_ entry: SyncLogEntry) {
        recentEvents.insert(entry, at: 0)
        if recentEvents.count > 50 { recentEvents.removeLast(recentEvents.count - 50) }
        logger.log("CloudKit \(entry.typeDescription, privacy: .public): \(entry.succeeded ? "ok" : "fail", privacy: .public)")
    }
}

struct SyncLogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let type: NSPersistentCloudKitContainer.EventType
    let succeeded: Bool
    let message: String

    var typeDescription: String {
        switch type {
        case .setup:  return NSLocalizedString("セットアップ", comment: "")
        case .import: return NSLocalizedString("取り込み", comment: "")
        case .export: return NSLocalizedString("書き出し", comment: "")
        @unknown default: return "?"
        }
    }
}
