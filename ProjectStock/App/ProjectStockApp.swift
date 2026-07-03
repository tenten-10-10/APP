import SwiftUI

@main
struct ProjectStockApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var container: ServiceContainer
    @StateObject private var settings: AppSettings

    init() {
        // MUST be first: install the uncaught-exception recorder and read the
        // crash-loop counter before anything can crash.
        LaunchCrashGuard.beginLaunch()

        // Tests/UI-tests run on isolated in-memory stores without CloudKit so
        // they are deterministic and need no iCloud account (spec §17, §19).
        let useInMemory = AppConfig.isUITesting
        // Disable CloudKit if the previous launch crashed before stabilising, so
        // the app always opens locally instead of crash-looping.
        let cloudKitEnabled = !AppConfig.isRunningTests && !LaunchCrashGuard.safeModeActive
        let persistence = PersistenceController(inMemory: useInMemory, cloudKitEnabled: cloudKitEnabled)
        let appSettings = AppSettings.shared
        _container = StateObject(wrappedValue: ServiceContainer(persistence: persistence, settings: appSettings))
        _settings = StateObject(wrappedValue: appSettings)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(container)
                .environmentObject(container.syncMonitor)
                .environmentObject(container.stocktake)
                .environmentObject(container.webBorrow)
                .environmentObject(settings)
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
