import Foundation
import CoreData
import Combine
import CloudKit

/// Composition root. Builds and owns every service and shared piece of state,
/// and is injected into the SwiftUI environment. Keeping construction in one
/// place keeps the wiring (MVVM + Repository/Service, spec §2) explicit.
final class ServiceContainer: ObservableObject {

    let persistence: PersistenceController
    let device: DeviceIdentity
    let settings: AppSettings

    let router: StoreRouter
    let inventory: InventoryService
    let folders: FolderService
    let locations: LocationService
    let projects: ProjectService
    let aliases: CodeAliasService
    let sampleData: SampleDataBuilder
    let backups: BackupService
    let qrExport: QRExportService
    let scanRouter: ScanResultRouter
    let stocktake: StocktakeCoordinator
    let sharing: CloudSharingService
    let webBorrow: WebBorrowInbox

    let syncMonitor: CloudKitSyncMonitor

    private var cancellables = Set<AnyCancellable>()

    init(persistence: PersistenceController,
         device: DeviceIdentity = .shared,
         settings: AppSettings = .shared) {
        self.persistence = persistence
        self.device = device
        self.settings = settings

        let router = StoreRouter(persistence: persistence)
        let inventory = InventoryService(device: device, router: router)
        let generator = PublicCodeGenerator()
        let aliases = CodeAliasService(generator: generator, router: router)

        let projectService = ProjectService(router: router, inventory: inventory)

        self.router = router
        self.inventory = inventory
        self.folders = FolderService()
        self.locations = LocationService(inventory: inventory)
        self.projects = projectService
        self.aliases = aliases
        self.sampleData = SampleDataBuilder(projects: projectService,
                                            inventory: inventory, aliases: aliases, router: router)
        self.backups = BackupService(projects: projectService, inventory: inventory,
                                     aliases: aliases, router: router)
        self.qrExport = QRExportService()
        self.scanRouter = ScanResultRouter(aliases: aliases)
        self.stocktake = StocktakeCoordinator(inventory: inventory)
        self.sharing = CloudSharingService(persistence: persistence, router: router, projectService: projectService)
        self.syncMonitor = CloudKitSyncMonitor(persistence: persistence)

        // Layer B: the public web borrow form's inbox. Built last so it can
        // capture the container's write helper / notification refresh.
        var writeHook: ((@escaping (NSManagedObjectContext) throws -> Void) -> Result<Void, Error>)!
        var notifyHook: (() -> Void)!
        self.webBorrow = WebBorrowInbox(
            backend: BorrowBackend(),
            viewContext: persistence.viewContext,
            settings: settings,
            aliases: aliases,
            inventory: inventory,
            sharing: self.sharing,
            router: router,
            write: { work in writeHook(work) },
            refreshNotifications: { notifyHook() }
        )
        writeHook = { [unowned self] work in self.performWrite(author: "webborrow", work) }
        notifyHook = { [unowned self] in self.refreshLoanNotifications() }

        // Accept incoming CloudKit share invitations into the shared store.
        NotificationCenter.default.publisher(for: .projectStockDidReceiveShareMetadata)
            .compactMap { $0.userInfo?[ShareAcceptanceKeys.metadata] as? CKShare.Metadata }
            .sink { [weak self] metadata in
                self?.sharing.acceptShare(metadata: metadata) { _ in }
            }
            .store(in: &cancellables)
    }

    var viewContext: NSManagedObjectContext { persistence.viewContext }

    // MARK: - Write helper

    /// Perform a mutation on a background context and save (spec §9: background
    /// context writes). Objects from the view context are re-resolved into the
    /// background context by `objectID` inside the block.
    @discardableResult
    func performWrite(author: String = "app",
                      _ work: @escaping (NSManagedObjectContext) throws -> Void) -> Result<Void, Error> {
        let context = persistence.newTaskContext(author: author)
        var result: Result<Void, Error> = .success(())
        context.performAndWait {
            do {
                try work(context)
                if context.hasChanges { try context.save() }
            } catch {
                context.rollback()
                result = .failure(error)
            }
        }
        return result
    }

    /// Resolve a view-context object into another context.
    func resolve<T: NSManagedObject>(_ object: T, in context: NSManagedObjectContext) -> T? {
        try? context.existingObject(with: object.objectID) as? T
    }

    /// One-time migration (1.2.11): move demo/お試し projects out of the
    /// CloudKit-mirrored private store into the local never-synced store.
    /// Demo data is disposable and deterministic, so the "move" is: delete the
    /// cloud copy (the deletion propagates to iCloud, freeing quota) and
    /// re-seed a fresh sample project into the local store. Skipped when the
    /// user already deleted the demo, and never repeated once it succeeds.
    func migrateSampleDataToLocalStoreIfNeeded() {
        let flag = "sampleDataLocalStoreMigrationV1"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        // Without a local store there is nowhere to migrate to — try again on a
        // later launch instead of burning the one-shot flag.
        guard persistence.localStore != nil else { return }
        let result = performWrite(author: "sampleMigration") { ctx in
            let request: NSFetchRequest<Project> = Project.fetchRequest()
            request.predicate = NSPredicate(format: "isSample == YES")
            let samples = (try? ctx.fetch(request)) ?? []
            let cloudSamples = samples.filter { !self.persistence.isInLocalStore($0) }
            guard !cloudSamples.isEmpty else { return }
            for sample in cloudSamples { ctx.delete(sample) }
            _ = try self.sampleData.makeSampleProject(in: ctx, owner: self.settings.effectiveOperatorName)
        }
        if case .success = result { UserDefaults.standard.set(true, forKey: flag) }
    }

    // MARK: - Backups (同期・共有事故への備え)

    /// Daily local snapshot of every real project — the safety net against
    /// shared-project data loss (a member's deletion or a sync conflict
    /// propagates to everyone; iCloud can't bring the records back, this can).
    /// Cheap no-op when the last backup is fresher than ~20h.
    func runAutoBackupIfNeeded() {
        let key = "lastAutoBackupAt"
        if let last = UserDefaults.standard.object(forKey: key) as? Date,
           Date().timeIntervalSince(last) < 20 * 3600 { return }
        let context = persistence.newTaskContext(author: "backup")
        let backups = self.backups
        context.perform {
            guard let document = try? backups.snapshot(in: context),
                  !document.projects.isEmpty,
                  (try? backups.writeBackup(document)) != nil else { return }
            UserDefaults.standard.set(Date(), forKey: key)
        }
    }

    /// Manual backup from 設定 > バックアップ. Synchronous; returns the file.
    func createBackupNow() -> Result<URL, Error> {
        let context = persistence.newTaskContext(author: "backup")
        var result: Result<URL, Error> = .failure(AppError.underlying("backup failed"))
        context.performAndWait {
            do {
                let document = try backups.snapshot(in: context)
                let url = try backups.writeBackup(document)
                UserDefaults.standard.set(Date(), forKey: "lastAutoBackupAt")
                result = .success(url)
            } catch {
                result = .failure(error)
            }
        }
        return result
    }

    /// Restore every project in a backup file as NEW projects (never merges).
    func restoreBackup(from url: URL, actor: String) -> Result<Void, Error> {
        do {
            let document = try backups.loadDocument(from: url)
            let outcome = performWrite(author: "restore") { ctx in
                try self.backups.restore(document, actor: actor, in: ctx)
            }
            if case .success = outcome { recomputeAllProjects() }
            return outcome
        } catch {
            return .failure(error)
        }
    }

    /// Seed the demo project once for App Store screenshot runs (`-snapshotData`).
    /// No-op if any project already exists so reruns stay idempotent.
    func seedSnapshotDataIfNeeded() {
        _ = performWrite(author: "snapshot") { ctx in
            let request: NSFetchRequest<Project> = Project.fetchRequest()
            request.fetchLimit = 1
            if ((try? ctx.count(for: request)) ?? 0) > 0 { return }
            _ = try self.sampleData.makeShowcaseProjects(in: ctx)
        }
        recomputeAllProjects()
    }

    // MARK: - Recompute on launch / remote change (spec §11)

    func recomputeAllProjects() {
        let context = persistence.newTaskContext(author: "recompute")
        context.performAndWait {
            let request: NSFetchRequest<Project> = Project.fetchRequest()
            guard let projects = try? context.fetch(request) else { return }
            for project in projects {
                self.inventory.recomputeAll(in: project)
            }
            if context.hasChanges { try? context.save() }
        }
    }

    // MARK: - Loan notifications

    /// Re-sync local notifications for outstanding loan due-dates with the
    /// current ledger state (call on launch and after any checkout / return).
    func refreshLoanNotifications() {
        let context = viewContext
        context.perform {
            let notices = self.inventory.activeLoans(in: context).compactMap { $0.notice }
            NotificationService.shared.sync(notices: notices)
        }
    }

    // MARK: - Expiry notifications

    /// Re-sync local notifications for lot expiry dates with the current
    /// inventory state (call on launch and after any lot is created/updated).
    /// Uses the "expiry-" prefix so it never clobbers loan notifications.
    func refreshExpiryNotifications() {
        let context = viewContext
        context.perform {
            let notices = self.inventory.expiringLots(in: context)
                .compactMap { self.inventory.expiryNotice(for: $0) }
            NotificationService.shared.syncExpiry(notices: notices)
        }
    }
}
