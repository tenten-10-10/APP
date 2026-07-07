import SwiftUI
import CoreData

struct SettingsView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var syncMonitor: CloudKitSyncMonitor
    @EnvironmentObject private var entitlements: EntitlementService
    @State private var showingPaywall = false
    @EnvironmentObject private var webBorrow: WebBorrowInbox

    @State private var deviceName = DeviceIdentity.shared.displayName
    @State private var shareItem: ShareableFile?
    @State private var confirmingExport = false
    @State private var confirmingDemoDelete = false
    @State private var showTutorial = false
    @State private var error: PresentableError?
    @State private var infoAlert: String?
    @AppStorage("hideFirstRunGuide") private var hideFirstRunGuide = false

    // Demo (お試し) projects, so the delete row only shows when there are any.
    // Entity-NAME-based request (see HomeView): the `sortDescriptors:` convenience
    // form resolves via NSManagedObject.entity(), which returns nil under CloudKit
    // mirroring and crashes SwiftUI with "A fetch request must have an entity."
    @FetchRequest(fetchRequest: {
        let r = Project.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Project.createdAt, ascending: true)]
        r.predicate = NSPredicate(format: "isSample == YES")
        return r
    }(), animation: .default) private var demoProjects: FetchedResults<Project>

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
                // Surface WHAT is wrong right here — the red badge alone gives
                // the user nothing to act on.
                if case .error(let reason) = syncMonitor.syncState {
                    Text(reason).font(.caption).foregroundColor(.orange)
                }
                NavigationLink(NSLocalizedString("診断ログ", comment: "")) { DiagnosticsView() }
            }

            if EntitlementService.teamPlanEnabled {
                Section {
                    Button {
                        showingPaywall = true
                    } label: {
                        HStack {
                            Label(NSLocalizedString("タナミル チーム", comment: ""), systemImage: "person.2.fill")
                            Spacer()
                            Text(entitlements.hasTeamFeatures
                                    ? NSLocalizedString("登録済み", comment: "")
                                    : NSLocalizedString("未登録", comment: ""))
                                .foregroundColor(entitlements.hasTeamFeatures ? .green : .secondary)
                                .font(.footnote)
                        }
                    }
                } footer: {
                    Text(NSLocalizedString("プロジェクトの共有（チームでの共同管理）が使えるプランです。購入の復元や招待コードの引き換えもここから行えます。", comment: ""))
                        .font(.caption2)
                }
            }

            Section {
                Picker(NSLocalizedString("既定サイズ", comment: ""), selection: $settings.defaultSizePresetRaw) {
                    ForEach(QRSizePreset.allCases) { Text($0.localizedTitle).tag($0.rawValue) }
                }
                Picker(NSLocalizedString("既定DPI", comment: ""), selection: $settings.defaultDPI) {
                    ForEach([300, 600, 1200], id: \.self) { Text("\($0)").tag($0) }
                }
                Picker(NSLocalizedString("既定の誤り訂正", comment: ""), selection: $settings.defaultErrorCorrectionRaw) {
                    ForEach(QRErrorCorrectionLevel.allCases) { Text($0.localizedTitle).tag($0.rawValue) }
                }
            } header: {
                Text(NSLocalizedString("QRラベルの既定値", comment: ""))
            } footer: {
                Text(NSLocalizedString("通常は初期値のままで問題ありません。QRをとても小さく印刷する場合のみ調整してください。", comment: ""))
                    .font(.caption2)
            }

            Section(NSLocalizedString("操作", comment: "")) {
                Toggle(NSLocalizedString("触覚フィードバック", comment: ""), isOn: $settings.hapticsEnabled)
            }

            Section {
                Picker(NSLocalizedString("受け取り方", comment: ""), selection: $settings.webBorrowModeRaw) {
                    ForEach(WebBorrowMode.allCases) { Text($0.localizedTitle).tag($0.rawValue) }
                }
                NavigationLink {
                    WebBorrowInboxView()
                } label: {
                    HStack {
                        Label(NSLocalizedString("Web借用リクエスト", comment: ""), systemImage: "tray.and.arrow.down")
                        if webBorrow.pendingCount > 0 {
                            Spacer()
                            Text("\(webBorrow.pendingCount)")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(Color.red))
                                .foregroundColor(.white)
                        }
                    }
                }
            } header: {
                Text(NSLocalizedString("Web借用", comment: ""))
            } footer: {
                Text(NSLocalizedString("QRを読み取った人が、アプリなしでWebフォームから氏名・期間・貸出先を記入して借用を申請できます。届いた申請はここで確認できます。", comment: ""))
            }

            Section {
                Button {
                    createSample()
                } label: {
                    Label(NSLocalizedString("お試しデータを作成", comment: ""), systemImage: "wand.and.stars")
                }
                if !demoProjects.isEmpty {
                    Button(role: .destructive) {
                        confirmingDemoDelete = true
                    } label: {
                        Label(NSLocalizedString("お試しデータを削除", comment: ""), systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    .accessibilityIdentifier("deleteDemoDataButton")
                }
                Button { confirmingExport = true } label: {
                    Label(NSLocalizedString("データを書き出す (JSON)", comment: ""), systemImage: "square.and.arrow.up")
                }
                NavigationLink {
                    BackupListView()
                } label: {
                    Label(NSLocalizedString("バックアップ", comment: ""), systemImage: "externaldrive.badge.timemachine")
                }
            } header: {
                Text(NSLocalizedString("データ", comment: ""))
            } footer: {
                if !demoProjects.isEmpty {
                    Text(NSLocalizedString("お試しデータは使い方を確認するための架空のデータです。削除しても、自分で作成したプロジェクトには影響しません。共有・同期のトラブルに備えて、毎日自動でこの端末内にバックアップも保存されます。", comment: ""))
                } else {
                    Text(NSLocalizedString("共有・同期のトラブルに備えて、毎日自動でこの端末内にバックアップが保存されます。復元は「バックアップ」から。", comment: ""))
                }
            }

            Section(NSLocalizedString("情報", comment: "")) {
                Button {
                    hideFirstRunGuide = false   // ホームの初回ガイドも復活させる
                    showTutorial = true
                } label: {
                    Label(NSLocalizedString("使い方をもう一度見る", comment: ""), systemImage: "questionmark.circle")
                }
                NavigationLink(NSLocalizedString("プライバシーポリシー", comment: "")) { PrivacyPolicyView() }
                LabeledRow(title: NSLocalizedString("バージョン", comment: ""), value: "\(AppConfig.marketingVersion) (\(AppConfig.buildNumber))")
            }
        }
        .navigationTitle(NSLocalizedString("設定", comment: ""))
        .keyboardDoneBar()
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .alert(NSLocalizedString("お試しデータを削除しますか？", comment: ""), isPresented: $confirmingDemoDelete) {
            Button(NSLocalizedString("削除", comment: ""), role: .destructive) { deleteDemoData() }
            Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("お試し用プロジェクトと、その中の製品・QRラベル・履歴がすべて削除されます。自分で作成したプロジェクトには影響しません。", comment: ""))
        }
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
                ? NSLocalizedString("お試しデータは既に作成済みです", comment: "")
                : NSLocalizedString("お試しデータを作成しました", comment: "")
        case .failure(let err): error = PresentableError(err)
        }
    }

    /// Delete every demo (お試し) project. The Core Data model cascades from
    /// Project to its folders/products/units/labels/events, so this removes the
    /// demo data completely without touching user-created projects.
    private func deleteDemoData() {
        let result = container.performWrite { ctx in
            let req: NSFetchRequest<Project> = Project.fetchRequest()
            req.predicate = NSPredicate(format: "isSample == YES")
            for project in try ctx.fetch(req) { ctx.delete(project) }
        }
        switch result {
        case .success:
            // Starting real operation now — bring the getting-started guide back.
            hideFirstRunGuide = false
            infoAlert = NSLocalizedString("お試しデータを削除しました", comment: "")
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
