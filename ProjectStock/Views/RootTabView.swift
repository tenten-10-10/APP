import SwiftUI

/// Five-tab root: Home · Projects · Scan · Activity · Settings.
struct RootTabView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @State private var showOnboarding = false
    @State private var deepLinkOutcome: ScanOutcomeBox?

    var body: some View {
        TabView {
            NavigationView {
                HomeView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(NSLocalizedString("ホーム", comment: ""), systemImage: "house") }

            NavigationView {
                ProjectsView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(NSLocalizedString("プロジェクト", comment: ""), systemImage: "folder") }

            NavigationView {
                ScanTabView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(NSLocalizedString("スキャン", comment: ""), systemImage: "qrcode.viewfinder") }

            NavigationView {
                ActivityView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(NSLocalizedString("活動", comment: ""), systemImage: "clock.arrow.circlepath") }

            NavigationView {
                SettingsView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(NSLocalizedString("設定", comment: ""), systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
        .sheet(item: $deepLinkOutcome) { box in
            ScanResultSheet(outcome: box.outcome)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            handleUniversalLink(activity.webpageURL)
        }
        .onOpenURL { url in
            handleUniversalLink(url)
        }
        .onAppear {
            if !settings.hasCompletedOnboarding && !AppConfig.isUITesting {
                showOnboarding = true
            }
        }
    }

    /// A Universal Link (`t.l0l0.app/<code>`) — scanned with the Camera app or
    /// tapped anywhere — is routed through the SAME resolver as the in-app
    /// scanner, then its result sheet (with the borrow/checkout actions) opens.
    private func handleUniversalLink(_ url: URL?) {
        guard let url else { return }
        let result = container.scanRouter.route(rawValue: url.absoluteString, in: container.viewContext)
        switch result {
        case .known(let alias), .unassigned(let alias), .retired(let alias):
            registerScan(alias)
            deepLinkOutcome = ScanOutcomeBox(outcome: result)
        case .unknownAppCode:
            deepLinkOutcome = ScanOutcomeBox(outcome: result)
        case .foreign:
            break // not one of our links — ignore
        }
    }

    private func registerScan(_ alias: CodeAlias) {
        let aliasID = alias.objectID
        _ = container.performWrite { ctx in
            guard let a = try ctx.existingObject(with: aliasID) as? CodeAlias else { return }
            container.aliases.registerScan(alias: a)
        }
    }
}
