import SwiftUI

@main
struct ProjectStockApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var container: ServiceContainer
    @StateObject private var settings: AppSettings

    init() {
        // Tests/UI-tests run on isolated in-memory stores without CloudKit so
        // they are deterministic and need no iCloud account (spec §17, §19).
        let useInMemory = AppConfig.isUITesting
        let cloudKitEnabled = !AppConfig.isRunningTests
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
                .environmentObject(settings)
                .environment(\.managedObjectContext, container.viewContext)
                .task {
                    // Rebuild quantity caches from the ledger and tidy temp
                    // export files on launch (spec §11, §16).
                    container.recomputeAllProjects()
                    container.qrExport.purgeOldExports()
                    container.syncMonitor.refreshAccountStatus()
                    container.refreshLoanNotifications()
                }
        }
    }
}
