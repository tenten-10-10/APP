import Foundation
import CoreData
import Combine

/// Coordinates the Layer B "web borrow" flow on the app side: it pulls the
/// borrow requests submitted through the public form (`t.l0l0.app/<code>`) for
/// the codes this device owns, and turns approved ones into real loans in the
/// inventory ledger.
///
/// Ownership: built and retained by `ServiceContainer`, injected into the
/// SwiftUI environment so the Home badge / inbox observe `pending` directly.
@MainActor
final class WebBorrowInbox: ObservableObject {

    /// Pending requests awaiting the owner's decision (manual mode) or that
    /// could not be applied automatically.
    @Published private(set) var pending: [WebBorrowRequest] = []
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    var pendingCount: Int { pending.count }

    enum WebBorrowError: LocalizedError {
        case codeNotFound
        case notLoanable
        case readOnly
        case unitUnavailable

        var errorDescription: String? {
            switch self {
            case .codeNotFound:    return NSLocalizedString("この番号に一致する現物が見つかりませんでした。", comment: "")
            case .notLoanable:     return NSLocalizedString("この番号は貸出に対応していません。", comment: "")
            case .readOnly:        return NSLocalizedString("このプロジェクトは読み取り専用のため反映できません。", comment: "")
            case .unitUnavailable: return NSLocalizedString("この個体は現在貸出できない状態です。", comment: "")
            }
        }
    }

    private let backend: BorrowBackend
    private let viewContext: NSManagedObjectContext
    private let settings: AppSettings
    private let aliases: CodeAliasService
    private let inventory: InventoryService
    private let sharing: CloudSharingService
    private let router: StoreRouter
    private let write: (@escaping (NSManagedObjectContext) throws -> Void) -> Result<Void, Error>
    private let refreshNotifications: () -> Void

    private var lastConvertError: String?

    nonisolated init(backend: BorrowBackend,
                     viewContext: NSManagedObjectContext,
                     settings: AppSettings,
                     aliases: CodeAliasService,
                     inventory: InventoryService,
                     sharing: CloudSharingService,
                     router: StoreRouter,
                     write: @escaping (@escaping (NSManagedObjectContext) throws -> Void) -> Result<Void, Error>,
                     refreshNotifications: @escaping () -> Void) {
        self.backend = backend
        self.viewContext = viewContext
        self.settings = settings
        self.aliases = aliases
        self.inventory = inventory
        self.sharing = sharing
        self.router = router
        self.write = write
        self.refreshNotifications = refreshNotifications
    }

    // MARK: - Refresh

    /// Pull the latest requests for our codes. In automatic mode, convert each
    /// pending request to a loan immediately; in manual mode, stage them in
    /// `pending` for the owner to approve or reject.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        errorMessage = nil

        let codes = activeCodes()
        guard !codes.isEmpty else { pending = []; return }

        let fetched: [WebBorrowRequest]
        do {
            fetched = try await backend.fetch(codes: codes)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let pendingRequests = fetched.filter { $0.isPending }

        if settings.webBorrowMode == .automatic {
            var remaining: [WebBorrowRequest] = []
            var appliedAny = false
            for request in pendingRequests {
                if await applyAndMark(request) {
                    appliedAny = true
                } else {
                    remaining.append(request)   // keep for manual handling
                }
            }
            pending = remaining
            if appliedAny { refreshNotifications() }
        } else {
            pending = pendingRequests
        }
    }

    // MARK: - Manual decisions

    func approve(_ request: WebBorrowRequest) async {
        if await applyAndMark(request) {
            pending.removeAll { $0.id == request.id }
            Haptics.success()
            refreshNotifications()
        } else {
            errorMessage = lastConvertError ?? NSLocalizedString("貸出として記録できませんでした。", comment: "")
        }
    }

    func reject(_ request: WebBorrowRequest) async {
        do {
            try await backend.mark(id: request.id, code: request.code, status: "rejected")
            pending.removeAll { $0.id == request.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Apply

    /// Convert one request to a loan and, on success, mark it `applied` on the
    /// backend so it is never processed twice. Returns `true` on success.
    private func applyAndMark(_ request: WebBorrowRequest) async -> Bool {
        let actor = settings.effectiveOperatorName
        // Capture the (value-type / read-only) dependencies as locals so the
        // write closure — which runs on a background Core Data queue — is not
        // main-actor bound.
        let aliases = self.aliases
        let inventory = self.inventory
        let sharing = self.sharing
        let router = self.router
        let result = write { ctx in
            try Self.convert(request, actor: actor, aliases: aliases,
                             inventory: inventory, sharing: sharing, router: router, in: ctx)
        }
        switch result {
        case .success:
            try? await backend.mark(id: request.id, code: request.code, status: "applied")
            return true
        case .failure(let error):
            lastConvertError = error.localizedDescription
            return false
        }
    }

    /// Record the loan in the ledger. Runs inside a background write context, so
    /// it is `nonisolated` and takes its dependencies explicitly.
    nonisolated private static func convert(_ request: WebBorrowRequest, actor: String,
                                            aliases: CodeAliasService,
                                            inventory: InventoryService,
                                            sharing: CloudSharingService,
                                            router: StoreRouter,
                                            in ctx: NSManagedObjectContext) throws {
        guard let alias = aliases.findAlias(forCode: request.code, in: ctx) else {
            throw WebBorrowError.codeNotFound
        }
        guard let project = alias.project else { throw WebBorrowError.notLoanable }
        guard sharing.canEdit(project) else { throw WebBorrowError.readOnly }

        let borrower = borrowerLabel(for: request)
        let noteText = noteText(for: request)
        let start = request.startDate
        let due = request.dueDate

        // Prefer a directly-assigned, available individual unit.
        if alias.targetType == .unit, let unit = alias.unit {
            guard inventory.resolvedStatus(for: unit) == .available else {
                throw WebBorrowError.unitUnavailable
            }
            inventory.checkout(unit: unit, actor: actor, borrower: borrower,
                               dueAt: due, note: noteText, occurredAt: start, in: ctx)
            return
        }

        // Otherwise resolve the product and create a lightweight representative
        // unit for this borrowed sample. We intentionally do NOT post a `.create`
        // (+1) event: the unit is checked out immediately (status → checkedOut,
        // which is not "on hand"), so no product's quantity total changes.
        guard let product = alias.product ?? alias.unit?.product else {
            throw WebBorrowError.notLoanable
        }
        let unit = StockUnit.make(in: ctx, serialNumber: borrower, product: product,
                                  project: project, location: product.defaultLocation)
        router.assignChild(unit, toSameStoreAs: project, in: ctx)
        inventory.checkout(unit: unit, actor: actor, borrower: borrower,
                           dueAt: due, note: noteText, occurredAt: start, in: ctx)
    }

    // MARK: - Helpers

    /// Every active public code known to this device, deduplicated and capped so
    /// the RPC payload stays reasonable.
    private func activeCodes() -> [String] {
        let request: NSFetchRequest<CodeAlias> = CodeAlias.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == YES")
        let found = (try? viewContext.fetch(request)) ?? []
        let codes = found.compactMap { $0.publicCode }.filter { !$0.isEmpty }
        return Array(Set(codes).prefix(2000))
    }

    nonisolated private static func borrowerLabel(for r: WebBorrowRequest) -> String {
        let name = r.trimmedBorrower.isEmpty ? NSLocalizedString("借り手", comment: "") : r.trimmedBorrower
        if let dest = r.trimmedDestination { return "\(name)（\(dest)）" }
        return name
    }

    nonisolated private static func noteText(for r: WebBorrowRequest) -> String {
        var lines = [NSLocalizedString("Webフォームから受付", comment: "")]
        if let dest = r.trimmedDestination {
            lines.append(String(format: NSLocalizedString("貸出先: %@", comment: ""), dest))
        }
        if let note = r.trimmedNote { lines.append(note) }
        return lines.joined(separator: "\n")
    }
}
