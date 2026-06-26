import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var syncMonitor: CloudKitSyncMonitor

    @State private var deviceName = DeviceIdentity.shared.displayName
    @State private var shareItem: ShareableFile?
    @State private var confirmingExport = false
    @State private var showTutorial = false
    @State private var error: PresentableError?
    @AppStorage("hideFirstRunGuide") private var hideFirstRunGuide = false

    var body: some View {
        Form {
            Section(NSLocalizedString("操作者", comment: "")) {
                TextField(NSLocalizedString("操作者表示名", comment: ""), text: $settings.operatorDisplayName)
                    .accessibilityIdentifier("operatorNameField")
                HStack {
                    TextField(NSLocalizedString("端末名", comment: ""), text: $deviceName)
                    Button(NSLocalizedString("保存", comment: "")) { DeviceIdentity.shared.updateDisplayName(deviceName) }
                        .font(.caption)
                }
            }

            Section(NSLocalizedString("iCloud", comment: "")) {
                HStack {
                    SyncStatusBadge(state: syncMonitor.syncState)
                    Spacer()
                    Button(NSLocalizedString("再確認", comment: "")) { syncMonitor.clearError() }.font(.caption)
                }
                Text(syncMonitor.accountState.localizedMessage).font(.caption).foregroundColor(.secondary)
                NavigationLink(NSLocalizedString("診断ログ", comment: "")) { DiagnosticsView() }
            }

            Section(NSLocalizedString("QRラベルの既定値", comment: "")) {
                Picker(NSLocalizedString("既定サイズ", comment: ""), selection: $settings.defaultSizePresetRaw) {
                    ForEach(QRSizePreset.allCases) { Text($0.localizedTitle).tag($0.rawValue) }
                }
                Picker(NSLocalizedString("既定DPI", comment: ""), selection: $settings.defaultDPI) {
                    ForEach([300, 600, 1200], id: \.self) { Text("\($0)").tag($0) }
                }
                Picker(NSLocalizedString("既定の誤り訂正", comment: ""), selection: $settings.defaultErrorCorrectionRaw) {
                    ForEach(QRErrorCorrectionLevel.allCases) { Text($0.localizedTitle).tag($0.rawValue) }
                }
            }

            Section(NSLocalizedString("操作", comment: "")) {
                Toggle(NSLocalizedString("触覚フィードバック", comment: ""), isOn: $settings.hapticsEnabled)
            }

            Section(NSLocalizedString("データ", comment: "")) {
                Button {
                    let result = container.performWrite { ctx in
                        _ = try container.sampleData.makeSampleProject(in: ctx, owner: settings.effectiveOperatorName)
                    }
                    if case .failure(let err) = result { error = PresentableError(err) }
                } label: {
                    Label(NSLocalizedString("サンプルデータを作成", comment: ""), systemImage: "wand.and.stars")
                }
                Button { confirmingExport = true } label: {
                    Label(NSLocalizedString("データを書き出す (JSON)", comment: ""), systemImage: "square.and.arrow.up")
                }
            }

            Section(NSLocalizedString("情報", comment: "")) {
                Button {
                    showTutorial = true
                } label: {
                    Label(NSLocalizedString("使い方をもう一度見る", comment: ""), systemImage: "questionmark.circle")
                }
                Button {
                    hideFirstRunGuide = false
                } label: {
                    Label(NSLocalizedString("はじめてガイドを再表示", comment: ""), systemImage: "sparkles")
                }
                NavigationLink(NSLocalizedString("プライバシーポリシー", comment: "")) { PrivacyPolicyView() }
                LabeledRow(title: NSLocalizedString("バージョン", comment: ""), value: "\(AppConfig.marketingVersion) (\(AppConfig.buildNumber))")
            }
        }
        .navigationTitle(NSLocalizedString("設定", comment: ""))
        .alert(NSLocalizedString("データを書き出しますか？", comment: ""), isPresented: $confirmingExport) {
            Button(NSLocalizedString("書き出す", comment: "")) { exportData() }
            Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("すべてのプロジェクトの在庫データをJSONファイルに書き出します。", comment: ""))
        }
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
        .fullScreenCover(isPresented: $showTutorial) {
            OnboardingView(isPresented: $showTutorial)
        }
        .errorAlert($error)
    }

    private func exportData() {
        do {
            let url = try DataExportService().exportJSON(context: container.viewContext)
            shareItem = ShareableFile(url: url)
        } catch { self.error = PresentableError(error) }
    }
}
