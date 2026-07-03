import SwiftUI
import UIKit

/// Sync diagnostics (spec §13, §16): shows recent CloudKit import/export events
/// and lets the user share a diagnostics text file that contains NO product
/// names or notes.
struct DiagnosticsView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var syncMonitor: CloudKitSyncMonitor
    @ObservedObject private var loadFailure = StoreLoadFailure.shared
    @State private var shareItem: ShareableFile?
    @State private var copied = false
#if DEBUG
    @State private var schemaResult: String?
    @State private var schemaRunning = false
#endif

    var body: some View {
        List {
#if DEBUG
            Section {
                Button {
                    schemaRunning = true; schemaResult = nil
                    DispatchQueue.global(qos: .userInitiated).async {
                        let message: String
                        do {
                            try container.persistence.initializeCloudKitSchemaForDevelopment()
                            message = "✅ 成功: CloudKit の Development 環境に全レコードタイプを作成しました。次は CloudKit Dashboard で「Deploy Schema Changes… → Production」を実行してください。"
                        } catch {
                            message = "❌ 失敗: \(error.localizedDescription)"
                        }
                        DispatchQueue.main.async { schemaResult = message; schemaRunning = false }
                    }
                } label: {
                    if schemaRunning {
                        HStack(spacing: 8) { ProgressView(); Text("スキーマ作成中… (数十秒かかります)") }
                    } else {
                        Label("CloudKitスキーマを初期化（開発環境）", systemImage: "wrench.and.screwdriver")
                    }
                }
                .disabled(schemaRunning)
                if let schemaResult {
                    Text(schemaResult).font(.caption).textSelection(.enabled)
                }
            } header: {
                Text("開発用ツール（DEBUGビルドのみ）")
            } footer: {
                Text("Xcodeから実行したときだけ表示されます。CloudKitのDevelopment環境に全レコードタイプ（CD_*）を作成します。")
            }
#endif
            if LaunchCrashGuard.safeModeActive || LaunchCrashGuard.lastException != nil {
                Section {
                    Label(NSLocalizedString("前回の起動でアプリが停止しました", comment: ""), systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundColor(.orange)
                    if LaunchCrashGuard.safeModeActive {
                        Text(NSLocalizedString("安全のため、今回はiCloud同期をオフにして起動しています。", comment: ""))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    if let ex = LaunchCrashGuard.lastException {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("停止した理由", comment: ""))
                                .font(.caption.weight(.semibold))
                            Text(ex)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                        }.padding(.vertical, 2)
                        Button { copyText(ex) } label: {
                            Label(copied ? NSLocalizedString("コピーしました", comment: "") : NSLocalizedString("この理由をコピー", comment: ""),
                                  systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                    }
                    Button { LaunchCrashGuard.resetForRetry() } label: {
                        Label(NSLocalizedString("次回起動で同期を再試行", comment: ""), systemImage: "arrow.clockwise")
                    }
                } header: {
                    Text(NSLocalizedString("クラッシュからの復帰", comment: ""))
                } footer: {
                    Text(NSLocalizedString("「停止した理由」の文面を開発者に送っていただけると、原因を特定できます。", comment: ""))
                        .font(.caption2)
                }
            }

            Section(NSLocalizedString("現在の状態", comment: "")) {
                SyncStatusBadge(state: syncMonitor.syncState)
                Text(syncMonitor.accountState.localizedMessage).font(.caption).foregroundColor(.secondary)
            }

            Section {
                LabeledRow(title: NSLocalizedString("iCloud同期", comment: ""),
                           value: container.persistence.cloudKitActive
                               ? NSLocalizedString("有効", comment: "")
                               : NSLocalizedString("停止中", comment: ""))
                LabeledRow(title: NSLocalizedString("コンテナID", comment: ""),
                           value: AppConfig.cloudKitContainerIdentifier)
                if let report = container.persistence.cloudKitFailureReport
                    ?? container.persistence.cloudKitLoadError.map({ CloudKitErrorMapper.rawDescription(for: $0) }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("同期が停止している理由", comment: ""))
                            .font(.caption.weight(.semibold))
                        Text(report)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text(NSLocalizedString("iCloud同期の詳細", comment: ""))
            } footer: {
                if container.persistence.cloudKitLoadError != nil {
                    Text(NSLocalizedString("この「理由」の文面を長押しでコピーして開発者に送っていただくと、原因を特定できます。", comment: ""))
                        .font(.caption2)
                }
            }

            if let error = loadFailure.lastError, container.persistence.cloudKitLoadError == nil {
                Section(NSLocalizedString("ストア読み込みエラー", comment: "")) {
                    Text(CloudKitErrorMapper.rawDescription(for: error))
                        .font(.system(.caption, design: .monospaced))
                }
            }

            Section(NSLocalizedString("最近の同期イベント", comment: "")) {
                if syncMonitor.recentEvents.isEmpty {
                    Text(NSLocalizedString("まだイベントはありません", comment: "")).foregroundColor(.secondary)
                }
                ForEach(syncMonitor.recentEvents) { entry in
                    HStack {
                        Image(systemName: entry.succeeded ? "checkmark.circle" : "exclamationmark.triangle")
                            .foregroundColor(entry.succeeded ? .green : .orange)
                        VStack(alignment: .leading) {
                            Text(entry.typeDescription).font(.caption)
                            Text(entry.message).font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(DateFormatters.short.string(from: entry.date)).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Button { copyDiagnostics() } label: {
                    Label(copied ? NSLocalizedString("コピーしました", comment: "") : NSLocalizedString("診断ログをコピー", comment: ""),
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Button { shareDiagnostics() } label: {
                    Label(NSLocalizedString("診断ログを共有", comment: ""), systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text(NSLocalizedString("コピーして貼り付ければ確実に送れます。診断ログには製品名やメモは含まれません。", comment: "")).font(.caption2)
            }
        }
        .navigationTitle(NSLocalizedString("診断", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
    }

    /// Copy the whole diagnostics text to the clipboard — the most reliable way
    /// to get it to the developer when AirDrop / file share is finicky.
    private func copyDiagnostics() { copyText(diagnosticsText()) }

    private func copyText(_ text: String) {
        UIPasteboard.general.string = text
        Haptics.success()
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func diagnosticsText() -> String {
        var lines: [String] = []
        lines.append("タナミル (ProjectStock) Diagnostics")
        lines.append("Version: \(AppConfig.marketingVersion) (\(AppConfig.buildNumber))")
        lines.append("CloudKit: \(container.persistence.cloudKitEnabled)")
        lines.append("CloudKitActive: \(container.persistence.cloudKitActive)")
        lines.append("SafeMode: \(LaunchCrashGuard.safeModeActive)")
        lines.append("Container: \(AppConfig.cloudKitContainerIdentifier)")
        if let ex = LaunchCrashGuard.lastException {
            lines.append("LastUncaughtException: \(ex)")
        }
        if let report = container.persistence.cloudKitFailureReport {
            lines.append("--- CloudKit load failure ---")
            lines.append(report)
        } else if let error = container.persistence.cloudKitLoadError {
            lines.append("CloudKitLoadError: \(CloudKitErrorMapper.rawDescription(for: error))")
        }
        lines.append("Account: \(syncMonitor.accountState)")
        lines.append("SyncState: \(syncMonitor.syncState.localizedTitle)")
        lines.append("Device: \(DeviceIdentity.shared.deviceID)")
        lines.append("--- events ---")
        for entry in syncMonitor.recentEvents {
            lines.append("\(DateFormatters.dateTime.string(from: entry.date)) \(entry.typeDescription) \(entry.succeeded ? "OK" : "FAIL") \(entry.message)")
        }
        return lines.joined(separator: "\n")
    }

    private func shareDiagnostics() {
        let text = diagnosticsText()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // ASCII filename: non-ASCII (Japanese) names can make AirDrop fail with
        // "AirDropを実行できませんでした" on the receiving side.
        let url = dir.appendingPathComponent("Tanamiru-diagnostics-\(QRExportService.dateStamp()).txt")
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
        shareItem = ShareableFile(url: url)
    }
}

/// In-app privacy policy (spec §12.7). The canonical document is
/// PRIVACY_POLICY_JA.md; this mirrors its essence for offline reading.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            Text(Self.body)
                .font(.callout)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(NSLocalizedString("プライバシーポリシー", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }

    static let body = """
    ProjectStock プライバシーポリシー（要約）

    ・本アプリは在庫データをお使いのiCloudアカウント（プライベートデータベース）に保存します。運営者のサーバーには送信しません。
    ・QRコードには商品名や数量などの内容は含まれず、短い不透明なIDのみが入ります。
    ・カメラはQRの読み取りにのみ使用し、映像を保存・送信しません。
    ・広告や解析のための第三者SDKは使用していません。端末IDはアプリ内で生成した識別子で、広告識別子は使いません。
    ・プロジェクトをiCloud共有した場合、共有相手はそのプロジェクトのデータを参照・編集（権限による）できます。
    ・書き出したファイルは一時領域に作成され、一定時間後に自動削除されます。

    完全版は配布パッケージ内の PRIVACY_POLICY_JA.md を参照してください。
    """
}
