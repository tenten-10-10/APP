import Foundation
import CoreData

/// The four+ outcomes of a scan (spec §8). `unknownAppCode` distinguishes a
/// well-formed ProjectStock code that simply isn't in the local stores yet
/// (e.g. not synced / different account) from a genuinely foreign QR.
public enum ScanOutcome {
    case known(CodeAlias)         // active, assigned to a target
    case unassigned(CodeAlias)    // active, not yet assigned
    case retired(CodeAlias)       // deactivated label
    case unknownAppCode(String)   // looks like ours, not found locally
    case foreign(String)          // not a ProjectStock code at all
}

/// Classifies a raw scanned string into a `ScanOutcome`. Pure: the caller is
/// responsible for persisting scan statistics and navigation.
public struct ScanResultRouter {

    let aliases: CodeAliasService

    init(aliases: CodeAliasService) {
        self.aliases = aliases
    }

    public func route(rawValue: String, in context: NSManagedObjectContext) -> ScanOutcome {
        // Accept both a bare code (old labels) and a Universal Link URL
        // (`https://t.l0l0.app/<code>` — new labels and deep links).
        let code = AppConfig.extractCode(fromScanned: rawValue)
        guard PublicCodeGenerator.looksLikeAppCode(code) else {
            return .foreign(rawValue)
        }
        guard let alias = aliases.findAlias(forCode: code, in: context) else {
            return .unknownAppCode(code)
        }
        if !alias.isActive {
            return .retired(alias)
        }
        if alias.targetType == .unassigned {
            return .unassigned(alias)
        }
        return .known(alias)
    }
}
