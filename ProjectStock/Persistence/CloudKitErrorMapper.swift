import Foundation
import CloudKit

/// Translates raw CloudKit / Core Data errors into short, non-technical
/// Japanese messages (spec §14: never show jargon directly, but keep the raw
/// description available for a details view).
enum CloudKitErrorMapper {

    static func userMessage(for error: Error) -> String {
        // `error as? CKError` bridges NSErrors in the CKErrorDomain too.
        if let ckError = error as? CKError {
            return message(for: ckError)
        }
        return NSLocalizedString("同期中に問題が発生しました。", comment: "")
    }

    private static func message(for error: CKError) -> String {
        switch error.code {
        case .notAuthenticated:
            return NSLocalizedString("iCloudにサインインしていません。", comment: "")
        case .accountTemporarilyUnavailable:
            return NSLocalizedString("iCloudアカウントが一時的に利用できません。", comment: "")
        case .networkUnavailable, .networkFailure:
            return NSLocalizedString("ネットワークに接続できません。", comment: "")
        case .quotaExceeded:
            return NSLocalizedString("iCloudの容量が不足しています。", comment: "")
        case .serverResponseLost, .serviceUnavailable, .requestRateLimited:
            return NSLocalizedString("iCloudが混み合っています。後で自動的に再試行します。", comment: "")
        case .zoneBusy:
            return NSLocalizedString("iCloudが処理中です。しばらくお待ちください。", comment: "")
        case .permissionFailure:
            return NSLocalizedString("この操作を行う権限がありません。", comment: "")
        case .managedAccountRestricted:
            return NSLocalizedString("この端末のポリシーによりiCloudが制限されています。", comment: "")
        case .partialFailure:
            return NSLocalizedString("一部のデータを同期できませんでした。", comment: "")
        case .changeTokenExpired:
            return NSLocalizedString("同期情報の再取得が必要です。自動的に再同期します。", comment: "")
        default:
            return NSLocalizedString("同期中に問題が発生しました。", comment: "")
        }
    }

    /// When CloudKit reports a *partial* failure (some records synced, some
    /// didn't — the generic "一部のデータを同期できませんでした"), dig out the
    /// DISTINCT underlying per-record reasons so diagnostics can pinpoint WHY.
    /// The usual culprit is a Production CloudKit schema that is missing a
    /// record type / field the app now uses (its `ServerErrorDescription` names
    /// the exact field). Returns nil when there is no per-record breakdown.
    static func partialFailureDetail(for error: Error) -> String? {
        var seen = Set<String>()
        var lines: [String] = []

        // Record the most specific reason on any error node in the tree — the
        // server description names the offending record type / field.
        func record(_ e: NSError) {
            let server = e.userInfo["ServerErrorDescription"] as? String
                ?? e.userInfo["CKErrorDescription"] as? String
            let reason = server
                ?? (e.domain == CKErrorDomain ? e.localizedDescription : e.localizedFailureReason)
            guard let reason, !reason.isEmpty else { return }
            let line = "[\(e.domain.replacingOccurrences(of: "Domain", with: ""))#\(e.code)] \(reason)"
            if seen.insert(line).inserted && lines.count < 5 { lines.append(line) }
        }

        // Walk underlying errors + CloudKit per-record errors + detailed errors.
        func walk(_ e: NSError, _ depth: Int) {
            guard depth < maxErrorDepth else { return }
            record(e)
            if let ck = e as? CKError, let byID = ck.partialErrorsByItemID {
                for value in byID.values { walk(value as NSError, depth + 1) }
            }
            if let detailed = e.userInfo["NSDetailedErrorsKey"] as? [NSError] {
                for d in detailed { walk(d, depth + 1) }
            }
            if let underlying = e.userInfo[NSUnderlyingErrorKey] as? NSError, underlying !== e {
                walk(underlying, depth + 1)
            }
        }

        walk(error as NSError, 0)
        return lines.isEmpty ? nil : lines.joined(separator: " ; ")
    }

    /// The single most aggressive dump we have: walk the ENTIRE error tree and
    /// print every domain/code plus EVERY userInfo key/value (truncated),
    /// including CloudKit's per-record errors. Core Data frequently hides the
    /// real reason for an export partial-failure behind a key we weren't
    /// explicitly reading (ServerErrorDescription / CKErrorDescription /
    /// NSDebugDescription live at different depths depending on the failure), so
    /// when diagnosing "why did this record fail to sync/share" we dump them ALL
    /// rather than guess which key holds it this time. Returns nil if the tree is
    /// somehow empty.
    static func fullDiagnosticDump(for error: Error) -> String? {
        var lines: [String] = []
        var seenPointers = Set<ObjectIdentifier>()
        deepDump(error as NSError, depth: 0, into: &lines, seen: &seenPointers)
        let joined = lines.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    private static func deepDump(_ error: NSError, depth: Int, into lines: inout [String], seen: inout Set<ObjectIdentifier>) {
        guard depth < maxErrorDepth else { lines.append(String(repeating: "  ", count: depth) + "…"); return }
        // Guard against self-referential error graphs (an error whose
        // NSUnderlyingError eventually points back to itself) — otherwise this
        // recurses until the stack overflows.
        let ptr = ObjectIdentifier(error)
        if !seen.insert(ptr).inserted { return }
        let indent = String(repeating: "  ", count: depth)
        lines.append("\(indent)• \(error.domain) #\(error.code)")

        // The keys that actually carry a human/server reason, most useful first.
        let reasonKeys = ["ServerErrorDescription", "CKErrorDescription",
                          NSDebugDescriptionErrorKey, NSLocalizedFailureReasonErrorKey]
        for key in reasonKeys {
            if let value = error.userInfo[key] as? String, !value.isEmpty {
                lines.append("\(indent)  \(shortKey(key)): \(truncate(value))")
            }
        }
        // Any OTHER string values in userInfo we didn't already print — this is
        // the safety net that catches whatever key holds the reason this time.
        for (key, value) in error.userInfo {
            guard !reasonKeys.contains(key), key != NSUnderlyingErrorKey,
                  key != "NSDetailedErrorsKey", key != "CKPartialErrorsByItemIDKey",
                  let string = value as? String, !string.isEmpty else { continue }
            lines.append("\(indent)  \(key): \(truncate(string))")
        }

        // CloudKit per-record errors — THE place a schema/field problem shows up.
        if let ck = error as? CKError, let byID = ck.partialErrorsByItemID {
            for (id, perRecord) in byID.prefix(8) {
                lines.append("\(indent)  record \(truncate("\(id)", max: 60)):")
                deepDump(perRecord as NSError, depth: depth + 2, into: &lines, seen: &seen)
            }
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            deepDump(underlying, depth: depth + 1, into: &lines, seen: &seen)
        }
        if let detailed = error.userInfo["NSDetailedErrorsKey"] as? [NSError] {
            for detail in detailed.prefix(8) { deepDump(detail, depth: depth + 1, into: &lines, seen: &seen) }
        }
    }

    private static func shortKey(_ key: String) -> String {
        switch key {
        case NSDebugDescriptionErrorKey: return "debug"
        case NSLocalizedFailureReasonErrorKey: return "reason"
        default: return key
        }
    }

    private static func truncate(_ s: String, max: Int = 240) -> String {
        s.count <= max ? s : String(s.prefix(max)) + "…"
    }

    /// The verbatim error text, shown only in a details / diagnostics screen.
    /// Core Data reports CloudKit setup failures as a generic 134060 whose real
    /// reason lives in the nested userInfo (debug description / underlying /
    /// detailed errors), so walk the whole tree — that's what actually pinpoints
    /// the cause.
    static func rawDescription(for error: Error) -> String {
        var lines: [String] = []
        appendDescription(of: error as NSError, depth: 0, into: &lines)
        return lines.joined(separator: "\n")
    }

    /// Deepest error nesting we'll print. Core Data / CloudKit error chains can
    /// be self-referential (an error's NSUnderlyingError eventually points back),
    /// so a hard depth cap is required — otherwise this recurses until the stack
    /// overflows and the app crashes on launch.
    private static let maxErrorDepth = 6

    private static func appendDescription(of error: NSError, depth: Int, into lines: inout [String]) {
        let indent = String(repeating: "  ", count: depth)
        lines.append("\(indent)\(error.domain) (\(error.code))")
        lines.append("\(indent)\(error.localizedDescription)")
        guard depth < maxErrorDepth else {
            lines.append("\(indent)…")
            return
        }

        let info = error.userInfo
        // The most useful field for CloudKit/Core Data setup failures.
        if let debug = info[NSDebugDescriptionErrorKey] as? String {
            lines.append("\(indent)» \(debug)")
        }
        // The CloudKit *server*'s own explanation of why a record was rejected —
        // e.g. a missing record type / field in the Production schema. This is
        // the single most useful line for a failed share, so surface it directly.
        if let server = info["ServerErrorDescription"] as? String {
            lines.append("\(indent)サーバー: \(server)")
        }
        if let ckDesc = info["CKErrorDescription"] as? String, ckDesc != info["ServerErrorDescription"] as? String {
            lines.append("\(indent)CK: \(ckDesc)")
        }
        if let reason = error.localizedFailureReason, reason != error.localizedDescription {
            lines.append("\(indent)理由: \(reason)")
        }
        // A share save fails as a CKError partialFailure whose per-record errors
        // carry the real reason; the generic top-level message alone is useless.
        if let ck = error as? CKError, let byID = ck.partialErrorsByItemID {
            for perRecord in byID.values.prefix(5) {
                let ns = perRecord as NSError
                if ns !== error { appendDescription(of: ns, depth: depth + 1, into: &lines) }
            }
        }
        if let underlying = info[NSUnderlyingErrorKey] as? NSError, underlying !== error {
            appendDescription(of: underlying, depth: depth + 1, into: &lines)
        }
        // NSDetailedErrorsKey isn't exposed as a Swift symbol; use its raw value.
        if let detailed = info["NSDetailedErrorsKey"] as? [NSError] {
            for detail in detailed.prefix(5) where detail !== error {
                appendDescription(of: detail, depth: depth + 1, into: &lines)
            }
        }
    }
}

/// App-level recoverable errors surfaced to the user with friendly text.
enum AppError: LocalizedError {
    case duplicateCode(String)
    case readOnlyProject
    case invalidHierarchy(String)
    case crossProjectReference
    case exportFailed(String)
    case shareCreationFailed(String)
    case shareURLUnavailable
    case cameraUnavailable
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .duplicateCode(let code):
            return String(format: NSLocalizedString("コード %@ は既に使用されています。", comment: ""), code)
        case .readOnlyProject:
            return NSLocalizedString("このプロジェクトは読み取り専用で共有されています。編集できません。", comment: "")
        case .invalidHierarchy(let detail):
            return String(format: NSLocalizedString("階層が無効です: %@", comment: ""), detail)
        case .crossProjectReference:
            return NSLocalizedString("別のプロジェクトのデータを参照することはできません。", comment: "")
        case .exportFailed(let detail):
            return String(format: NSLocalizedString("書き出しに失敗しました: %@", comment: ""), detail)
        case .shareCreationFailed(let detail):
            return String(format: NSLocalizedString("共有の作成に失敗しました: %@", comment: ""), detail)
        case .shareURLUnavailable:
            return NSLocalizedString("共有リンクを取得できませんでした。もう一度お試しください。", comment: "")
        case .cameraUnavailable:
            return NSLocalizedString("カメラを利用できません。", comment: "")
        case .underlying(let detail):
            return detail
        }
    }
}
