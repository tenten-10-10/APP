import SwiftUI

/// Five-tab root: Home · Projects · Scan · Activity · Settings.
struct RootTabView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnboarding = false
    @State private var deepLinkOutcome: ScanOutcomeBox?
    @State private var shareFeedback: CloudSharingService.AcceptFeedback?

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
        // Tell the recipient whether joining a shared project worked — the
        // acceptance used to be completely silent, so a failure was
        // indistinguishable from "the link did nothing".
        .onReceive(container.sharing.$acceptFeedback) { feedback in
            shareFeedback = feedback
        }
        .alert(item: $shareFeedback) { feedback in
            Alert(title: Text(feedback.success
                              ? NSLocalizedString("共有に参加しました", comment: "")
                              : NSLocalizedString("共有に参加できませんでした", comment: "")),
                  message: Text(feedback.message),
                  dismissButton: .default(Text(NSLocalizedString("OK", comment: ""))) {
                      container.sharing.acceptFeedback = nil
                  })
        }
        .onAppear {
            if !settings.hasCompletedOnboarding && !AppConfig.isUITesting {
                showOnboarding = true
            }
        }
        .onChange(of: scenePhase) { phase in
            // Re-check the web borrow inbox whenever the app comes to the front.
            if phase == .active && !AppConfig.isRunningTests {
                Task { await container.webBorrow.refresh() }
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
