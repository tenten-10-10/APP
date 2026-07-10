import SwiftUI

/// Five-tab root: Home · Projects · Scan · Activity · Settings.
struct RootTabView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var webBorrow: WebBorrowInbox
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnboarding = false
    @State private var deepLinkOutcome: ScanOutcomeBox?
    @State private var shareFeedback: CloudSharingService.AcceptFeedback?
    @State private var selection: Tab = .home
    @AppStorage("pcWebEnabled") private var pcWebEnabled = false
    /// Periodically re-check the Web borrow inbox while the app is open so a new
    /// request lights up the Home card / tab badge without the user having to
    /// background-and-foreground the app or open the inbox manually.
    private let inboxRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private enum Tab: Hashable { case home, projects, scan, activity, settings }

    var body: some View {
        TabView(selection: $selection) {
            NavigationView {
                // Switching the Home scan hero to select the Scan tab (rather
                // than pushing a second ScanTabView inside Home) avoids two
                // live scanner surfaces for one action.
                HomeView(onSwitchToScan: { selection = .scan })
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(NSLocalizedString("ホーム", comment: ""), systemImage: "house") }
            .badge(webBorrow.pendingCount)
            .tag(Tab.home)

            NavigationView {
                ProjectsView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(NSLocalizedString("プロジェクト", comment: ""), systemImage: "folder") }
            .tag(Tab.projects)

            NavigationView {
                ScanTabView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(NSLocalizedString("スキャン", comment: ""), systemImage: "qrcode.viewfinder") }
            .tag(Tab.scan)

            NavigationView {
                ActivityView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(NSLocalizedString("活動", comment: ""), systemImage: "clock.arrow.circlepath") }
            .tag(Tab.activity)

            NavigationView {
                SettingsView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(NSLocalizedString("設定", comment: ""), systemImage: "gearshape") }
            .tag(Tab.settings)
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
                // Keep the PC/Web viewer's read-only mirror fresh.
                if pcWebEnabled {
                    Task { try? await PCWebService.shared.pushSnapshot(container: container) }
                }
            }
        }
        .onChange(of: selection) { tab in
            // Switching TO the Home tab re-checks the inbox, so opening Home to
            // "see if anything came in" always shows a fresh count.
            if tab == .home && !AppConfig.isRunningTests {
                Task { await container.webBorrow.refresh() }
            }
        }
        .onReceive(inboxRefreshTimer) { _ in
            // Gentle background poll while active (the inbox has no push channel).
            if scenePhase == .active && !AppConfig.isRunningTests {
                Task { await container.webBorrow.refresh() }
            }
        }
    }

    /// A Universal Link (`t.l0l0.app/<code>`) — scanned with the Camera app or
    /// tapped anywhere — is routed through the SAME resolver as the in-app
    /// scanner, then its result sheet (with the borrow/checkout actions) opens.
    private func handleUniversalLink(_ url: URL?) {
        guard let url else { return }
        // Share-invite deep link: `t.l0l0.app/join?s=<icloud share url>`.
        // Routing the invite through OUR associated domain (not the raw
        // icloud.com link) guarantees the QR / link opens THIS app and accepts
        // the share in-place — it can never dead-end on the icloud.com web
        // sign-in page.
        if let shareURL = Self.shareURL(fromJoinLink: url) {
            container.sharing.joinShare(from: shareURL) { result in
                switch result {
                case .success:
                    container.sharing.acceptFeedback = .init(
                        success: true,
                        message: NSLocalizedString("共有プロジェクトに参加しました。同期が終わると「プロジェクト」一覧に表示されます。", comment: ""))
                case .failure(let err):
                    container.sharing.acceptFeedback = .init(
                        success: false,
                        message: String(format: NSLocalizedString("共有への参加に失敗しました（%@）。招待リンクをコピーして、プロジェクト画面の「招待リンクから参加」からもう一度お試しください。", comment: ""), err.localizedDescription))
                }
            }
            return
        }
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

    /// Extract the wrapped iCloud share URL from a `t.l0l0.app/join?s=…` link.
    static func shareURL(fromJoinLink url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              host == AppConfig.linkHost || host == "www.\(AppConfig.linkHost)",
              url.path.hasPrefix("/join"),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = comps.queryItems?.first(where: { $0.name == "s" })?.value else { return nil }
        return CloudSharingService.extractShareURL(from: raw)
    }

    private func registerScan(_ alias: CodeAlias) {
        let aliasID = alias.objectID
        _ = container.performWrite { ctx in
            guard let a = try ctx.existingObject(with: aliasID) as? CodeAlias else { return }
            container.aliases.registerScan(alias: a)
        }
    }
}
