import CoreData

/// Routes newly created objects into the correct persistent store so that a
/// Project and *all* of its descendants live together in one store. This is
/// what keeps owner data in the private store and participant (shared-to-me)
/// data in the shared store, and it guarantees we never create a relationship
/// that crosses CloudKit zones / stores.
///
/// Rules (spec §9):
///   * A brand-new Project the user creates → private store (they own it).
///   * Any child object → the SAME store as its owning Project.
struct StoreRouter {

    let persistence: PersistenceController

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    /// The store a new Project should be created in: always the private store
    /// (the local user is the owner). Returns nil only if stores failed to load.
    var newProjectStore: NSPersistentStore? {
        persistence.privateStore
            ?? persistence.container.persistentStoreCoordinator.persistentStores.first
    }

    /// The store an existing Project currently lives in.
    func store(for project: Project) -> NSPersistentStore? {
        // For a saved object this is its real backing store; for a freshly
        // inserted, not-yet-assigned object it is nil — fall back to the private
        // store, then to any loaded store, so assignment is never skipped.
        project.objectID.persistentStore
            ?? persistence.privateStore
            ?? persistence.container.persistentStoreCoordinator.persistentStores.first
    }

    /// Assign a newly created Project to the private store.
    func assignNewProject(_ project: Project, in context: NSManagedObjectContext) {
        if let store = newProjectStore {
            context.assign(project, to: store)
        }
    }

    /// Assign a newly created child object to the same store as its project.
    /// Call this for every Folder / Product / Location / StockUnit /
    /// InventoryEvent / CodeAlias right after insertion and before save.
    func assignChild(_ object: NSManagedObject, toSameStoreAs project: Project, in context: NSManagedObjectContext) {
        guard let store = store(for: project) else { return }
        context.assign(object, to: store)
    }

    /// Read-only check used by the UI to decide whether a project is editable.
    /// Objects in the shared store *may* still be read-only depending on the
    /// CKShare permission; this only tells you which store it is in.
    func isShared(_ project: Project) -> Bool {
        guard let shared = persistence.sharedStore else { return false }
        return store(for: project) === shared
    }
}
