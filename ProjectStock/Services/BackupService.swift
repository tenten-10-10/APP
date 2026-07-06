import Foundation
import CoreData

/// 端末内スナップショット — 共有・同期トラブルへの最後の砦。
///
/// CloudKit の共有プロジェクトは、メンバーの誤削除や同期の競合が「全員に」
/// 伝播する。iCloud 側に消えたデータを取り戻す手段はないので、アプリが
/// 毎日ローカル（Application Support/Backups）へ全プロジェクトの JSON
/// スナップショットを残し、設定 > バックアップ から
///  * いつでも手動バックアップ
///  * ファイルの書き出し（共有シート）
///  * 「新しいプロジェクトとして復元」
/// ができる。復元は既存データに一切マージしない（安全のため必ず新規
/// プロジェクトとして追加する）。写真と操作履歴はスナップショットに
/// 含まれない — 在庫の現在値・個体・ロット・QRコード・貸出中情報を守る
/// ことが目的（履歴の完全性は台帳イベントが担う）。
struct BackupService {

    static let schemaVersion = 1
    static let maxKeptBackups = 14

    let projects: ProjectService
    let inventory: InventoryService
    let aliases: CodeAliasService
    let router: StoreRouter

    // MARK: - Snapshot schema (v1) — stable Codable structs, ISO8601 dates

    struct Document: Codable {
        let v: Int
        let createdAt: Date
        let appVersion: String
        let projects: [ProjectSnapshot]
    }

    struct ProjectSnapshot: Codable {
        let name: String
        let note: String?
        let owner: String?
        let color: String
        let defaultMode: String
        let folders: [FolderSnapshot]
        let locations: [LocationSnapshot]
        let products: [ProductSnapshot]
        /// Active, unassigned (blank) QR codes owned by the project.
        let blankCodes: [String]
    }

    struct FolderSnapshot: Codable {
        let name: String
        let parentIndex: Int?
    }

    struct LocationSnapshot: Codable {
        let name: String
        let kind: String
        let parentIndex: Int?
        let note: String?
        let labels: [String]
    }

    struct ProductSnapshot: Codable {
        let name: String
        let sku: String?
        let note: String?
        let unit: String
        let mode: String
        let minimumStock: Double
        let folderIndex: Int?
        let locationIndex: Int?
        let quantity: Double
        let labels: [String]
        let units: [UnitSnapshot]
        let lots: [LotSnapshot]
    }

    struct UnitSnapshot: Codable {
        let serial: String
        let status: String
        let labels: [String]
        let borrower: String?
        let dueAt: Date?
    }

    struct LotSnapshot: Codable {
        let lotNumber: String
        let quantity: Double
        let expiresAt: Date?
        let labels: [String]
    }

    // MARK: - Capture

    /// Serialize every real (non-sample) project in the context.
    func snapshot(in context: NSManagedObjectContext) throws -> Document {
        let request: NSFetchRequest<Project> = Project.fetchRequest()
        request.predicate = NSPredicate(format: "isSample == NO")
        let allProjects = try context.fetch(request)
        let snapshots = allProjects.map { snapshotProject($0) }
        return Document(v: Self.schemaVersion, createdAt: Date(),
                        appVersion: AppConfig.marketingVersion, projects: snapshots)
    }

    private func snapshotProject(_ project: Project) -> ProjectSnapshot {
        let folders = sortedByDepth(project.folderArray, parent: { $0.parent })
        let folderIndex = indexMap(folders)
        let locations = sortedByDepth(project.locationArray, parent: { $0.parent })
        let locationIndex = indexMap(locations)

        let folderSnapshots = folders.map { folder in
            FolderSnapshot(name: folder.displayName,
                           parentIndex: folder.parent.flatMap { folderIndex[$0.objectID] })
        }
        let locationSnapshots = locations.map { location in
            LocationSnapshot(name: location.displayName,
                             kind: location.kind.rawValue,
                             parentIndex: location.parent.flatMap { locationIndex[$0.objectID] },
                             note: location.note,
                             labels: location.activeLabels.map(\.code))
        }
        let productSnapshots = project.productArray.filter { !$0.isArchived }.map { product in
            snapshotProduct(product, folderIndex: folderIndex, locationIndex: locationIndex)
        }
        let blank = project.labelArray
            .filter { $0.isActive && $0.targetType == .unassigned }
            .map(\.code)
        return ProjectSnapshot(name: project.displayName,
                               note: project.note,
                               owner: project.ownerDisplayName,
                               color: project.color.rawValue,
                               defaultMode: project.defaultTrackingMode.rawValue,
                               folders: folderSnapshots,
                               locations: locationSnapshots,
                               products: productSnapshots,
                               blankCodes: blank)
    }

    private func snapshotProduct(_ product: Product,
                                 folderIndex: [NSManagedObjectID: Int],
                                 locationIndex: [NSManagedObjectID: Int]) -> ProductSnapshot {
        let serialUnits = product.unitArray
            .filter { !$0.isLot && ($0.status == .available || $0.status == .checkedOut) }
            .map { unit -> UnitSnapshot in
                let loan = inventory.currentLoan(for: unit)
                return UnitSnapshot(serial: unit.displaySerial,
                                    status: unit.status.rawValue,
                                    labels: unit.activeLabels.map(\.code),
                                    borrower: loan?.borrower,
                                    dueAt: loan?.dueAt)
            }
        let lots = product.lotArray
            .filter { $0.lotQuantity > 0 || $0.expiresAt != nil }
            .map { lot in
                LotSnapshot(lotNumber: lot.lotNumberDisplay,
                            quantity: lot.lotQuantity,
                            expiresAt: lot.expiresAt,
                            labels: lot.activeLabels.map(\.code))
            }
        return ProductSnapshot(name: product.displayName,
                               sku: product.sku,
                               note: product.note,
                               unit: product.unitLabel,
                               mode: product.trackingMode.rawValue,
                               minimumStock: product.minimumStock,
                               folderIndex: product.folder.flatMap { folderIndex[$0.objectID] },
                               locationIndex: product.defaultLocation.flatMap { locationIndex[$0.objectID] },
                               quantity: product.currentQuantity,
                               labels: product.activeLabels.map(\.code),
                               units: serialUnits,
                               lots: lots)
    }

    // MARK: - Restore

    /// Recreate every project in the document as a NEW project (named
    /// 「◯◯（復元）」). Never merges into existing data. QR codes are re-created
    /// with their original code strings so printed labels keep working —
    /// unless the code still exists somewhere (then it is skipped; the
    /// existing label wins).
    @discardableResult
    func restore(_ document: Document, actor: String,
                 in context: NSManagedObjectContext) throws -> [Project] {
        try document.projects.map { try restoreProject($0, actor: actor, in: context) }
    }

    private func restoreProject(_ snapshot: ProjectSnapshot, actor: String,
                                in context: NSManagedObjectContext) throws -> Project {
        let name = String(format: NSLocalizedString("%@（復元）", comment: ""), snapshot.name)
        let project = projects.createProject(name: name,
                                             ownerDisplayName: snapshot.owner ?? actor,
                                             color: ProjectColor(raw: snapshot.color),
                                             defaultMode: TrackingMode(raw: snapshot.defaultMode),
                                             in: context)
        project.note = snapshot.note ?? ""

        var folders: [Folder] = []
        for f in snapshot.folders {
            let folder = Folder.make(in: context, name: f.name, project: project)
            if let pi = f.parentIndex, folders.indices.contains(pi) { folder.parent = folders[pi] }
            router.assignChild(folder, toSameStoreAs: project, in: context)
            folders.append(folder)
        }

        var locations: [Location] = []
        for l in snapshot.locations {
            let location = Location.make(in: context, name: l.name, project: project,
                                         kind: LocationKind(raw: l.kind))
            if let pi = l.parentIndex, locations.indices.contains(pi) { location.parent = locations[pi] }
            location.note = l.note
            router.assignChild(location, toSameStoreAs: project, in: context)
            for code in l.labels { attachLabel(code, to: .location(location), project: project, in: context) }
            locations.append(location)
        }

        for p in snapshot.products {
            let product = Product.make(in: context, name: p.name, project: project,
                                       sku: p.sku ?? "", unitName: p.unit,
                                       trackingMode: TrackingMode(raw: p.mode))
            product.note = p.note ?? ""
            product.minimumStock = p.minimumStock
            if let fi = p.folderIndex, folders.indices.contains(fi) { product.folder = folders[fi] }
            if let li = p.locationIndex, locations.indices.contains(li) { product.defaultLocation = locations[li] }
            router.assignChild(product, toSameStoreAs: project, in: context)

            switch product.trackingMode {
            case .quantity:
                if p.quantity > 0 {
                    inventory.setInitialStock(product: product, quantity: p.quantity,
                                              location: product.defaultLocation, actor: actor,
                                              note: NSLocalizedString("バックアップから復元", comment: ""),
                                              in: context)
                }
            case .lot:
                for lot in p.lots {
                    let restored = inventory.createLot(product: product, lotNumber: lot.lotNumber,
                                                       quantity: lot.quantity, expiresAt: lot.expiresAt,
                                                       location: product.defaultLocation, actor: actor,
                                                       note: NSLocalizedString("バックアップから復元", comment: ""),
                                                       in: context)
                    if let restored {
                        for code in lot.labels { attachLabel(code, to: .unit(restored), project: project, in: context) }
                    }
                }
            case .individual:
                for u in p.units {
                    let unit = StockUnit.make(in: context, serialNumber: u.serial,
                                              product: product, project: project,
                                              location: product.defaultLocation)
                    router.assignChild(unit, toSameStoreAs: project, in: context)
                    inventory.registerUnit(unit, location: product.defaultLocation, actor: actor, in: context)
                    if UnitStatus(raw: u.status) == .checkedOut {
                        inventory.checkout(unit: unit, actor: actor,
                                           borrower: u.borrower ?? "", dueAt: u.dueAt, in: context)
                    }
                    for code in u.labels { attachLabel(code, to: .unit(unit), project: project, in: context) }
                }
            }
            for code in p.labels { attachLabel(code, to: .product(product), project: project, in: context) }
        }

        for code in snapshot.blankCodes where !aliases.codeExists(code, in: context) {
            let alias = CodeAlias.make(in: context, publicCode: code, project: project)
            router.assignChild(alias, toSameStoreAs: project, in: context)
        }
        return project
    }

    /// Re-create a QR label with its ORIGINAL code so already-printed labels
    /// keep scanning to the restored item. Skipped when the code still exists
    /// (restore-as-copy while the original survives): codes are globally
    /// unique, and the surviving original must keep priority.
    private func attachLabel(_ code: String, to target: CodeAliasService.AliasTarget,
                             project: Project, in context: NSManagedObjectContext) {
        guard !code.isEmpty, !aliases.codeExists(code, in: context) else { return }
        let alias = CodeAlias.make(in: context, publicCode: code, project: project)
        router.assignChild(alias, toSameStoreAs: project, in: context)
        try? aliases.assign(alias: alias, to: target)
    }

    // MARK: - Ordering helpers

    /// Parents before children, so parentIndex always points at an
    /// already-emitted element (same idea as ProjectService.duplicate).
    private func sortedByDepth<T: NSManagedObject>(_ items: [T], parent: (T) -> T?) -> [T] {
        func depth(_ item: T) -> Int {
            var d = 0
            var current = parent(item)
            var guardCount = 0
            while let c = current, guardCount < 4096 { d += 1; current = parent(c); guardCount += 1 }
            return d
        }
        return items.sorted { depth($0) < depth($1) }
    }

    private func indexMap<T: NSManagedObject>(_ items: [T]) -> [NSManagedObjectID: Int] {
        Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.objectID, $0.offset) })
    }

    // MARK: - Files

    static var backupDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Backups", isDirectory: true)
    }

    struct BackupFile: Identifiable, Equatable {
        let url: URL
        let createdAt: Date
        let size: Int
        var id: URL { url }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Write a snapshot to disk and rotate old files (keep the newest
    /// `maxKeptBackups`). Returns the written file URL.
    @discardableResult
    func writeBackup(_ document: Document) throws -> URL {
        let dir = Self.backupDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = dir.appendingPathComponent("tanamiru-backup-\(formatter.string(from: document.createdAt)).json")
        let data = try Self.encoder().encode(document)
        try data.write(to: url, options: .atomic)
        rotate()
        return url
    }

    func loadDocument(from url: URL) throws -> Document {
        let data = try Data(contentsOf: url)
        let document = try Self.decoder().decode(Document.self, from: data)
        guard document.v <= Self.schemaVersion else {
            throw AppError.underlying(NSLocalizedString("このバックアップは新しいバージョンのアプリで作成されています。アプリを更新してから復元してください。", comment: ""))
        }
        return document
    }

    /// Newest first.
    func listBackups() -> [BackupFile] {
        let dir = Self.backupDirectory
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                return BackupFile(url: url,
                                  createdAt: values?.creationDate ?? .distantPast,
                                  size: values?.fileSize ?? 0)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func deleteBackup(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func rotate() {
        let files = listBackups()
        guard files.count > Self.maxKeptBackups else { return }
        for file in files.dropFirst(Self.maxKeptBackups) {
            deleteBackup(at: file.url)
        }
    }
}
