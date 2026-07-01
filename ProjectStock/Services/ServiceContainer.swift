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
