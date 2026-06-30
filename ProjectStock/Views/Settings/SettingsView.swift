import SwiftUI
import CoreData

struct SettingsView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var syncMonitor: CloudKitSyncMonitor

    @State private var deviceName = DeviceIdentity.shared.displayName
    @State private var shareItem: ShareableFile?
    @State private var confirmingExport = false
    @State private var showTutorial = false
    @State private var error: PresentableError?
    @State private var infoAlert: String?
    @AppStorage("hideFirstRunGuide") private var hideFirstRunGuide = false

    var body: some View {
        Form {
            Section {
                TextField(NSLocalizedString("操作者表示名", comment: ""), text: $settings.operatorDisplayName)
                    .accessibilityIdentifier("operatorNameField")
                HStack {
                    TextField(NSLocalizedString("端末名", comment: ""), text: $deviceName)
                    Button(NSLocalizedString("保存", comment: "")) { DeviceIdentity.shared.updateDisplayName(deviceName) }
                        .font(.caption)
                }
            } header: {
                Text(NSLocalizedString("操作者", comment: ""))
            } footer: {
                Text(NSLocalizedString("「操作者表示名」は、プロジェクトを共有して複数人で使うとき、入出庫などの操作履歴に「誰がやったか」として表示されます。", comment: ""))
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
                    createSample()
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
        .alert(infoAlert ?? "", isPresented: Binding(get: { infoAlert != nil },
                                                     set: { if !$0 { infoAlert = nil } })) {
            Button(NSLocalizedString("OK", comment: "")) { infoAlert = nil }
        }
        .errorAlert($error)
    }

    private func createSample() {
        var existed = false
        let result = container.performWrite { ctx in
            let req: NSFetchRequest<Project> = Project.fetchRequest()
            req.predicate = NSPredicate(format: "isSample == YES")
            req.fetchLimit = 1
            if ((try? ctx.count(for: req)) ?? 0) > 0 { existed = true; return }
            _ = try container.sampleData.makeSampleProject(in: ctx, owner: settings.effectiveOperatorName)
        }
        switch result {
        case .success:
            infoAlert = existed
                ? NSLocalizedString("サンプルデータは既に作成済みです", comment: "")
                : NSLocalizedString("サンプルデータを作成しました", comment: "")
        case .failure(let err): error = PresentableError(err)
        }
    }

    private func exportData() {
        do {
            let url = try DataExportService().exportJSON(context: container.viewContext)
            shareItem = ShareableFile(url: url)
        } catch { self.error = PresentableError(error) }
    }
}
