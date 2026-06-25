import SwiftUI

/// Five-tab root: Home · Projects · Scan · Activity · Settings.
struct RootTabView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @State private var showOnboarding = false

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
        .onAppear {
            if !settings.hasCompletedOnboarding && !AppConfig.isUITesting {
                showOnboarding = true
            }
        }
    }
}
