import SwiftUI

// MARK: - RootView

/// サイズクラスに応じて iPhone（NavigationStack）と iPad（3カラム）を切り替える。
struct RootView: View {

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AuthService.self) private var auth

    var body: some View {
        Group {
            if auth.isSignedIn {
                // サインイン済み: 通常のアプリ UI。
                Group {
                    if horizontalSizeClass == .regular {
                        iPadSplitRoot()
                    } else {
                        iPhoneStackRoot()
                    }
                }
                .modifier(GlobalPaywallModifier())
            } else {
                // サインアウト中（本番のみ到達。Mock は自動サインインする）。
                SignInView()
            }
        }
    }
}

// MARK: - iPhone root

/// iPhone: ホームを起点にしたナビゲーションスタック（企画フロー）。
private struct iPhoneStackRoot: View {
    var body: some View {
        NavigationStack {
            HomeView()
        }
    }
}

// MARK: - iPad root (3-column)

/// iPad: 左（チャット/フェーズ/ページ）｜中央（キャンバス）｜右（インスペクタ）。
private struct iPadSplitRoot: View {

    @State private var sidebarSelection: SidebarItem? = .home
    @State private var selectedPage: Int = 1
    @State private var selectedPanelID: PanelSpec.ID?

    var body: some View {
        NavigationSplitView {
            // 左カラム: ナビゲーションとプロジェクト要素。
            SidebarColumn(selection: $sidebarSelection)
                .navigationTitle("PlotName AI")
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
        } content: {
            // 中央カラム: 選択に応じたメイン編集エリア。
            CenterColumn(
                selection: sidebarSelection,
                selectedPage: $selectedPage
            )
            .navigationSplitViewColumnWidth(min: 360, ideal: 560)
        } detail: {
            // 右カラム: インスペクタ。
            InspectorColumn(
                selectedPage: selectedPage,
                selectedPanelID: $selectedPanelID
            )
            .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Sidebar

/// 左カラムの項目。
enum SidebarItem: String, CaseIterable, Identifiable {
    case home       // プロジェクト一覧
    case story      // ストーリーチャット
    case phases     // 13フェーズ
    case pages      // ページプラン
    case usage      // 使用状況

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "プロジェクト"
        case .story: return "ストーリー"
        case .phases: return "13フェーズ"
        case .pages: return "ページプラン"
        case .usage: return "使用状況"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "rectangle.stack"
        case .story: return "bubble.left.and.text.bubble.right"
        case .phases: return "square.grid.3x3"
        case .pages: return "doc.on.doc"
        case .usage: return "chart.bar"
        }
    }
}

private struct SidebarColumn: View {
    @Binding var selection: SidebarItem?
    @Environment(ProjectStore.self) private var store

    var body: some View {
        List(selection: $selection) {
            Section("作業") {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }

            if let bundle = store.selectedBundle {
                Section("現在のプロジェクト") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bundle.project.title)
                            .font(.headline)
                        Text(bundle.project.format.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Center column

private struct CenterColumn: View {
    let selection: SidebarItem?
    @Binding var selectedPage: Int

    var body: some View {
        switch selection {
        case .home, .none:
            HomeView()
        case .story:
            StoryChatView()
        case .phases:
            PhaseGridView()
        case .pages:
            PagePlanView(selectedPage: $selectedPage)
        case .usage:
            UsageView()
        }
    }
}

// MARK: - Inspector column

private struct InspectorColumn: View {
    let selectedPage: Int
    @Binding var selectedPanelID: PanelSpec.ID?
    @Environment(ProjectStore.self) private var store

    var body: some View {
        if let bundle = store.selectedBundle {
            NameCanvasView(
                bundle: bundle,
                selectedPage: selectedPage,
                selectedPanelID: $selectedPanelID
            )
        } else {
            ContentUnavailableView(
                "プロジェクト未選択",
                systemImage: "sidebar.right",
                description: Text("左のリストからプロジェクトを選んでください。")
            )
        }
    }
}

// MARK: - Global paywall

/// どの画面からでもペイウォールを提示できるようにするモディファイア。
private struct GlobalPaywallModifier: ViewModifier {
    @Environment(BillingService.self) private var billing

    func body(content: Content) -> some View {
        @Bindable var billing = billing
        return content
            .sheet(item: $billing.paywallTrigger) { trigger in
                PaywallView(trigger: trigger)
            }
    }
}

#Preview("iPhone") {
    RootView()
        .environmentForPreview()
}

// regular サイズクラスを強制し、Canvas のデバイスに依らず 3 カラム構成を確認できる。
// 実機レイアウト確認は Canvas でも iPad デバイスを選ぶこと。
#Preview("iPad 3カラム") {
    RootView()
        .environment(\.horizontalSizeClass, .regular)
        .environmentForPreview(plan: .pro)
}

#Preview("ダーク") {
    RootView()
        .environmentForPreview()
        .preferredColorScheme(.dark)
}
