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

    private static func appendDescription(of error: NSError, depth: Int, into lines: inout [String]) {
        let indent = String(repeating: "  ", count: depth)
        lines.append("\(indent)\(error.domain) (\(error.code))")
        lines.append("\(indent)\(error.localizedDescription)")

        let info = error.userInfo
        // The most useful field for CloudKit/Core Data setup failures.
        if let debug = info[NSDebugDescriptionErrorKey] as? String {
            lines.append("\(indent)» \(debug)")
        }
        if let reason = error.localizedFailureReason, reason != error.localizedDescription {
            lines.append("\(indent)理由: \(reason)")
        }
        if let underlying = info[NSUnderlyingErrorKey] as? NSError {
            appendDescription(of: underlying, depth: depth + 1, into: &lines)
        }
        if let detailed = info[NSDetailedErrorsKey] as? [NSError] {
            for detail in detailed.prefix(5) {
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
