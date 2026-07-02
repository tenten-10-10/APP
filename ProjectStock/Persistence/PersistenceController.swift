import CoreData
import CloudKit
import Combine
import os.log

/// Owns the `NSPersistentCloudKitContainer` and its two SQLite stores:
///
/// * **Private store** — mirrors the user's own CloudKit private database
///   (`.private` scope). Projects the user owns live here.
/// * **Shared store** — mirrors records shared *to* the user via CKShare
///   (`.shared` scope). Projects others shared with this user live here.
///
/// Both stores use the same managed object model / default configuration, so
/// the same entities sync in either direction. New child objects must be
/// assigned (`context.assign(_:to:)`) to the SAME store the owning Project
/// lives in — that routing is done by `StoreRouter`.
final class PersistenceController {

    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    /// Resolved persistent stores, populated after `loadPersistentStores`.
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?

    /// Whether CloudKit mirroring is active. Disabled for tests / previews and
    /// when running unsigned where the iCloud entitlement is unavailable.
    let cloudKitEnabled: Bool

    /// True when a CloudKit-backed store failed to load and was re-added as a
    /// plain local store. Sharing must not be offered in this state — the
    /// mirroring metadata isn't there and share() fails with a file error.
    private(set) var cloudKitFallbackActive = false

    /// CloudKit is compiled in AND every store actually loaded with mirroring.
    var cloudKitActive: Bool { cloudKitEnabled && !cloudKitFallbackActive }

    private let logger = Logger(subsystem: "ProjectStock", category: "Persistence")

    // MARK: - Init

    /// - Parameters:
    ///   - inMemory: use in-memory stores (tests / SwiftUI previews).
    ///   - cloudKitEnabled: attach CloudKit options to the store descriptions.
    init(inMemory: Bool = false, cloudKitEnabled: Bool = true) {
        self.cloudKitEnabled = cloudKitEnabled && !inMemory

        container = NSPersistentCloudKitContainer(name: "ProjectStock")

        guard let privateDescription = container.persistentStoreDescriptions.first else {
            fatalError("ProjectStock: missing default store description")
        }

        if inMemory {
            configureInMemory(privateDescription)
        } else {
            configureOnDisk(privateDescription)
        }

        loadStores()
        configureViewContext()
    }

    // MARK: - Store configuration

    private func configureInMemory(_ privateDescription: NSPersistentStoreDescription) {
        // Two distinct in-memory stores so StoreRouter can be exercised even in
        // tests. History tracking is not available for in-memory stores.
        privateDescription.type = NSInMemoryStoreType
        privateDescription.url = URL(fileURLWithPath: "/dev/null/private")
        privateDescription.configuration = "Default"
        privateDescription.cloudKitContainerOptions = nil

        let sharedDescription = privateDescription.copy() as! NSPersistentStoreDescription
        sharedDescription.url = URL(fileURLWithPath: "/dev/null/shared")

        container.persistentStoreDescriptions = [privateDescription, sharedDescription]
    }

    private func configureOnDisk(_ privateDescription: NSPersistentStoreDescription) {
        let storeFolder = privateDescription.url!.deletingLastPathComponent()
        privateDescription.url = storeFolder.appendingPathComponent("private.sqlite")
        privateDescription.configuration = "Default"

        let sharedDescription = privateDescription.copy() as! NSPersistentStoreDescription
        sharedDescription.url = storeFolder.appendingPathComponent("shared.sqlite")

        // Persistent history + remote-change notifications are required for
        // CloudKit mirroring and to keep the two stores merged.
        for description in [privateDescription, sharedDescription] {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        if cloudKitEnabled {
            let containerID = AppConfig.cloudKitContainerIdentifier

            let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
            privateOptions.databaseScope = .private
            privateDescription.cloudKitContainerOptions = privateOptions

            let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
            sharedOptions.databaseScope = .shared
            sharedDescription.cloudKitContainerOptions = sharedOptions
        } else {
            privateDescription.cloudKitContainerOptions = nil
            sharedDescription.cloudKitContainerOptions = nil
        }

        container.persistentStoreDescriptions = [privateDescription, sharedDescription]
    }

    private func loadStores() {
        var failed: [NSPersistentStoreDescription] = []
        container.loadPersistentStores { [weak self] description, error in
            guard let self else { return }
            if let error = error {
                self.logger.error("Store '\(description.url?.lastPathComponent ?? "?", privacy: .public)' failed to load: \(error.localizedDescription, privacy: .public). Falling back to local-only storage.")
                failed.append(description)
            } else {
                self.mapStore(description)
            }
        }

        // If a CloudKit-backed store failed to load — no iCloud account, the
        // container isn't provisioned yet, offline, or an entitlement mismatch —
        // retry it as a plain local store. This guarantees there is ALWAYS a
        // usable store, so a write never hits a coordinator with zero / ambiguous
        // stores. (That would raise an uncatchable Obj-C exception on save, not a
        // Swift error, which is exactly the create/sample-data crash.)
        for description in failed {
            if description.cloudKitContainerOptions != nil { cloudKitFallbackActive = true }
            description.cloudKitContainerOptions = nil
            do {
                let store = try container.persistentStoreCoordinator.addPersistentStore(
                    ofType: description.type,
                    configurationName: description.configuration,
                    at: description.url,
                    options: description.options)
                assignStore(store, for: description)
            } catch {
                StoreLoadFailure.shared.record(error)
            }
        }
    }

    /// Map an already-loaded store (looked up by URL) to the private/shared slot.
    private func mapStore(_ description: NSPersistentStoreDescription) {
        guard let url = description.url,
              let store = container.persistentStoreCoordinator.persistentStore(for: url) else { return }
        assignStore(store, for: description)
    }

    /// Record a store as private or shared, by CloudKit scope or store filename.
    private func assignStore(_ store: NSPersistentStore, for description: NSPersistentStoreDescription) {
        if description.cloudKitContainerOptions?.databaseScope == .shared
            || (description.url?.lastPathComponent.contains("shared") ?? false) {
            sharedStore = store
        } else {
            privateStore = store
        }
    }

    private func configureViewContext() {
        let viewContext = container.viewContext
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        viewContext.transactionAuthor = "viewContext"
        viewContext.name = "viewContext"
        // NOTE: deliberately NOT pinned to a query generation. A pinned WAL
        // snapshot can be invalidated by checkpoints from the CloudKit
        // mirroring writer (or any large write batch), after which reads —
        // including NSPersistentCloudKitContainer.share() — fail with
        // NSCocoaErrorDomain 256 「ファイル "private.sqlite" を開けませんでした」.
    }

    // MARK: - Contexts

    /// A background context configured for writes. Always do mutations on a
    /// background context and let `automaticallyMergesChangesFromParent` fold
    /// the changes back into the view context.
    func newTaskContext(author: String = "app") -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.transactionAuthor = author
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    var viewContext: NSManagedObjectContext { container.viewContext }

    // MARK: - Store routing helpers

    /// The persistent store backing a given object, if known.
    func store(for object: NSManagedObject) -> NSPersistentStore? {
        object.objectID.persistentStore
    }

    /// Whether an object lives in the shared store (i.e. it was shared TO us).
    func isInSharedStore(_ object: NSManagedObject) -> Bool {
        guard let shared = sharedStore else { return false }
        return object.objectID.persistentStore === shared
    }
}

// MARK: - Preview / test factories

extension PersistenceController {
    /// In-memory controller with no CloudKit, seeded with one sample project —
    /// for SwiftUI previews.
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.viewContext
        let device = DeviceIdentity.shared
        let services = ServiceContainer(persistence: controller, device: device)
        _ = try? services.sampleData.makeSampleProject(in: context)
        try? context.save()
        return controller
    }()

    /// In-memory controller with empty stores — for unit tests.
    static func makeInMemory() -> PersistenceController {
        PersistenceController(inMemory: true)
    }
}

/// Records a non-fatal store-load failure so the UI can offer recovery instead
/// of the app crashing on launch (spec §14: no data-losing `fatalError`).
final class StoreLoadFailure: ObservableObject {
    static let shared = StoreLoadFailure()
    @Published private(set) var lastError: Error?
    func record(_ error: Error) {
        DispatchQueue.main.async { self.lastError = error }
    }
}
