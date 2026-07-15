import Foundation
import CoreData

/// PC/Web 閲覧ビューア（読み取り専用）の同期クライアント。スマホに見えている
/// 在庫（自分の＋共有で参加中のプロジェクト）をスナップショットとして Supabase に
/// push し、PC側は QR ペアリングでそれを閲覧する。書き戻しは無い（一方向）。
///
/// バックエンドは既存の Web借用と同じ anon キー + SECURITY DEFINER RPC 方式
/// （`pc-web/tanamiru_pcweb_viewer.sql`）。
final class PCWebService {
    static let shared = PCWebService()

    private let baseURL = AppConfig.webBorrowBaseURL
    private let anonKey = AppConfig.webBorrowAnonKey
    private let session: URLSession = .shared

    /// このアカウント（端末）を識別する鍵。ペアリングとスナップショットの束縛に使う。
    var accountKey: String { DeviceIdentity.shared.deviceID }

    // MARK: - Pairing (phone authorizes a PC that showed a QR)

    /// PCが表示した `t.l0l0.app/pair?c=CODE` の CODE を受け取り、そのPCログインを
    /// 自分のアカウントに許可する。成功後は最新スナップショットも push する。
    func authorize(pairCode: String, container: ServiceContainer) async throws {
        let code = pairCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await rpcString("tanamiru_pcweb_authorize",
                                         body: ["p_pair_code": code, "p_account_key": accountKey])
        if result == "invalid" {
            throw PCWebError.invalidCode
        }
        try? await pushSnapshot(container: container)
    }

    /// 与えられたスキャン文字列が PCログイン用のペアリングリンクなら CODE を返す。
    static func pairCode(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased(),
              host == AppConfig.linkHost || host == "www.\(AppConfig.linkHost)",
              url.path.hasPrefix("/pair"),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = comps.queryItems?.first(where: { $0.name == "c" })?.value,
              !code.isEmpty else { return nil }
        return code
    }

    // MARK: - Snapshot push (phone → cloud)

    /// スマホに見えている在庫を丸ごとスナップショット化して push する。
    func pushSnapshot(container: ServiceContainer) async throws {
        let ctx = container.viewContext
        let inventory = container.inventory
        let sharing = container.sharing
        let payload: [String: Any] = await ctx.perform {
            Self.buildSnapshot(ctx: ctx, inventory: inventory, sharing: sharing)
        }
        _ = try await rpcData("tanamiru_pcweb_push_snapshot",
                              body: ["p_account_key": accountKey,
                                     "p_payload": payload,
                                     "p_app_version": AppConfig.marketingVersion])
    }

    /// Core Data を読み取ってスナップショット辞書を作る。呼び出しは ctx のキュー上。
    private static func buildSnapshot(ctx: NSManagedObjectContext,
                                      inventory: InventoryService,
                                      sharing: CloudSharingService) -> [String: Any] {
        let req = Project.fetchRequest()
        req.predicate = NSPredicate(format: "archivedAt == nil")
        req.sortDescriptors = [NSSortDescriptor(keyPath: \Project.updatedAt, ascending: false)]
        let projects = ((try? ctx.fetch(req)) ?? []).filter { !$0.isSample }

        let iso = ISO8601DateFormatter()
        let dayFmt = DateFormatter(); dayFmt.dateStyle = .medium; dayFmt.timeStyle = .none
        let dtFmt = DateFormatter(); dtFmt.dateStyle = .medium; dtFmt.timeStyle = .short

        var projectDicts: [[String: Any]] = []
        for p in projects {
            let permission = sharing.permission(for: p)
            let isShared = permission != .notShared

            let folders: [[String: Any]] = p.folderArray.map {
                ["id": $0.objectID.uriString, "name": $0.displayName]
            }
            let locations: [[String: Any]] = p.locationArray.map {
                ["id": $0.objectID.uriString, "name": $0.displayName, "path": $0.breadcrumb]
            }

            var products: [[String: Any]] = []
            var units: [[String: Any]] = []
            var loans: [[String: Any]] = []
            var lowCount = 0

            for product in p.productArray {
                if product.isLowStock { lowCount += 1 }
                products.append([
                    "id": product.objectID.uriString,
                    "name": product.displayName,
                    "folder": product.folder?.displayName ?? "",
                    "mode": product.trackingMode.localizedTitle,
                    "qty": product.currentQuantity.quantityString,
                    "unit": product.unitName ?? "",
                    "minStock": product.minimumStock.quantityString,
                    "low": product.isLowStock
                ])
                for unit in product.unitArray {
                    let loan = inventory.currentLoan(for: unit)
                    let status = loan != nil ? NSLocalizedString("貸出中", comment: "")
                                             : NSLocalizedString("在庫", comment: "")
                    units.append([
                        "id": unit.objectID.uriString,
                        "product": product.displayName,
                        "kind": unit.isLot ? "lot" : "unit",
                        "title": unit.displayTitle,
                        "status": status,
                        "location": unit.location?.breadcrumb ?? "",
                        "expires": unit.expiresAt.map { dayFmt.string(from: $0) } ?? ""
                    ])
                    if let loan = loan {
                        loans.append([
                            "title": unit.displayTitle,
                            "product": product.displayName,
                            "borrower": loan.borrowerDisplay,
                            "since": dtFmt.string(from: loan.since),
                            "due": loan.dueAt.map { dtFmt.string(from: $0) } ?? "",
                            "overdue": loan.isOverdue
                        ])
                    }
                }
            }

            projectDicts.append([
                "id": p.objectID.uriString,
                "name": p.displayName,
                "shared": isShared,
                "folders": folders,
                "locations": locations,
                "products": products,
                "units": units,
                "loans": loans,
                "counts": ["products": products.count, "units": units.count,
                           "lowStock": lowCount, "overdue": loans.filter { ($0["overdue"] as? Bool) == true }.count]
            ])
        }

        return [
            "generatedAt": iso.string(from: Date()),
            "appVersion": AppConfig.marketingVersion,
            "projects": projectDicts
        ]
    }

    // MARK: - RPC

    private func rpcData(_ name: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/rest/v1/rpc/\(name)") else { throw PCWebError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 25
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PCWebError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }

    private func rpcString(_ name: String, body: [String: Any]) async throws -> String {
        let data = try await rpcData(name, body: body)
        // RPC returns a JSON string like "ok" / "invalid".
        if let s = try? JSONDecoder().decode(String.self, from: data) { return s }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\"\n ")) ?? ""
    }
}

private extension NSManagedObjectID {
    /// Stable string id for the web snapshot (opaque; only used as a row key).
    var uriString: String { uriRepresentation().absoluteString }
}

enum PCWebError: LocalizedError {
    case invalidCode, notConfigured, badResponse(Int)
    var errorDescription: String? {
        switch self {
        case .invalidCode:  return NSLocalizedString("このQRは期限切れか無効です。PC側でもう一度表示し直してください。", comment: "")
        case .notConfigured: return NSLocalizedString("PC連携の設定が見つかりません。", comment: "")
        case .badResponse(let c): return String(format: NSLocalizedString("PC連携に失敗しました（%d）。", comment: ""), c)
        }
    }
}
