import SwiftUI

/// Four-tab root (spec §12.1).
struct RootTabView: View {
    @EnvironmentObject private var container: ServiceContainer

    var body: some View {
        TabView {
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
    }
}
