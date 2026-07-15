import SwiftUI
import CoreData
import AudioToolbox

/// ハンディモードの動作モード。起動時は必ず「照会」（非破壊）で開き、書き込み
/// モードは色・音・触覚で常時自己申告する — 置き忘れた端末での誤出庫を構造的に
/// 防ぐ（誤操作ゼロ設計）。
enum HandyMode: String, CaseIterable, Identifiable {
    case lookup, receive, consume
    var id: String { rawValue }

    var title: String {
        switch self {
        case .lookup:  return NSLocalizedString("照会", comment: "handy mode")
        case .receive: return NSLocalizedString("入庫", comment: "handy mode")
        case .consume: return NSLocalizedString("出庫", comment: "handy mode")
        }
    }

    var systemImage: String {
        switch self {
        case .lookup:  return "magnifyingglass"
        case .receive: return "tray.and.arrow.down.fill"
        case .consume: return "tray.and.arrow.up.fill"
        }
    }

    var color: Color {
        switch self {
        case .lookup:  return Color(red: 0.23, green: 0.34, blue: 0.6)   // 落ち着いた青
        case .receive: return Color(red: 0.18, green: 0.49, blue: 0.25)  // 緑
        case .consume: return Color(red: 0.8, green: 0.42, blue: 0.1)    // オレンジ
        }
    }
}

/// One committed operation in this handy session — enough to undo it (the
/// ledger event's objectID) and to render the history list.
struct HandyEntry: Identifiable {
    let id = UUID()
    let eventID: NSManagedObjectID?
    let title: String     // product name
    let detail: String    // e.g. "+5 入庫"
    let date = Date()
    var reversed = false
}

/// The last-scan result card overlaid on the camera. `actions` render as big
/// buttons on the card (登録する / 開く / 無視 …).
struct HandyCard: Identifiable {
    enum Kind { case success, info, warning, error }
    enum Action {
        case register(code: String)
        case ignore(code: String)
        case openProduct(NSManagedObjectID)
    }
    struct CardButton: Identifiable {
        let id = UUID()
        let label: String
        let action: Action
    }
    let id = UUID()
    let kind: Kind
    let title: String
    var subtitle: String?
    var actions: [CardButton] = []

    var tint: Color {
        switch kind {
        case .success: return Color.green
        case .info:    return Color.blue
        case .warning: return Color.orange
        case .error:   return Color.red
        }
    }
}

/// In-memory session ledger (like StocktakeCoordinator, but per-presentation).
/// Owned by HandyModeView as @StateObject; nothing here touches Core Data.
@MainActor final class HandySession: ObservableObject {
    @Published var entries: [HandyEntry] = []   // newest first

    func add(_ entry: HandyEntry) { entries.insert(entry, at: 0) }

    func markReversed(_ id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].reversed = true
    }

    /// The next undoable operation (newest non-reversed with a ledger event).
    var undoable: HandyEntry? { entries.first { !$0.reversed && $0.eventID != nil } }

    var receiveCount: Int { entries.filter { !$0.reversed && $0.detail.contains(NSLocalizedString("入庫", comment: "")) }.count }
    var consumeCount: Int { entries.filter { !$0.reversed && $0.detail.contains(NSLocalizedString("出庫", comment: "")) }.count }
}

/// Scan feedback sounds. AudioServices system sounds respect the ringer/silent
/// switch; haptics run in parallel so the feedback works muted too. Unknown
/// IDs are silently ignored by iOS — worst case is haptics-only, never a crash.
enum HandySound {
    static func lookup()  { play(1057) }        // Tink
    static func receive() { play(1103) }        // short tick (higher)
    static func consume() { play(1104) }        // short tick (lower)
    static func error()   { play(1073) }        // busy-ish double buzz
    private static func play(_ id: SystemSoundID) {
        guard !AppConfig.isUITesting else { return }
        AudioServicesPlaySystemSound(id)
    }
}
