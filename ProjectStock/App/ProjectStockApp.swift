import SwiftUI

@main
struct ProjectStockApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var container: ServiceContainer
    @StateObject private var settings: AppSettings
    @StateObject private var entitlements: EntitlementService

    init() {
        // Keep recording the reason of any uncaught launch exception (for the
        // diagnostics screen) — but we NO LONGER disable CloudKit after a crash.
        // The launch crash that motivated "safe mode" is fixed (fetch requests
        // are entity-name based), and auto-disabling sync made the app need a
        // throw-away first launch ("restart once to sync") — which we remove here.
        LaunchCrashGuard.beginLaunch()
        LaunchCrashGuard.markStable()   // clear any leftover crash counter immediately

        // Tests/UI-tests run on isolated in-memory stores without CloudKit so
        // they are deterministic and need no iCloud account (spec §17, §19).
        let useInMemory = AppConfig.isUITesting
        // CloudKit is ON whenever we're not running automated tests. iCloud
        // availability itself is handled gracefully by PersistenceController's
        // local fallback, so there is nothing to "restart" for.
        let cloudKitEnabled = !AppConfig.isRunningTests
        let persistence = PersistenceController(inMemory: useInMemory, cloudKitEnabled: cloudKitEnabled)
        let appSettings = AppSettings.shared
        _container = StateObject(wrappedValue: ServiceContainer(persistence: persistence, settings: appSettings))
        _settings = StateObject(wrappedValue: appSettings)
        _entitlements = StateObject(wrappedValue: EntitlementService())
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(container)
                .environmentObject(container.syncMonitor)
                .environmentObject(container.stocktake)
                .environmentObject(container.webBorrow)
                .environmentObject(settings)
                .environmentObject(entitlements)
                .environment(\.managedObjectContext, container.viewContext)
                .task {
                    // Seed a populated demo project for App Store screenshot runs.
                    if AppConfig.isSnapshot { container.seedSnapshotDataIfNeeded() }
                    // Rebuild quantity caches from the ledger and tidy temp
                    // export files on launch (spec §11, §16).
                    container.recomputeAllProjects()
                    container.qrExport.purgeOldExports()
                    container.syncMonitor.refreshAccountStatus()
                    container.refreshLoanNotifications()
                    container.refreshExpiryNotifications()
                    // Pull any web borrow requests (and auto-apply if enabled).
                    if !AppConfig.isRunningTests { await container.webBorrow.refresh() }
                }
                .task {
                    // Survived a few seconds without crashing → this launch is
                    // stable, so the next one may try CloudKit again.
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    LaunchCrashGuard.markStable()
                }
        }
    }
}
