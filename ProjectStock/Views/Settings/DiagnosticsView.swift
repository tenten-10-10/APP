import SwiftUI

/// Sync diagnostics (spec §13, §16): shows recent CloudKit import/export events
/// and lets the user share a diagnostics text file that contains NO product
/// names or notes.
struct DiagnosticsView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var syncMonitor: CloudKitSyncMonitor
    @ObservedObject private var loadFailure = StoreLoadFailure.shared
    @State private var shareItem: ShareableFile?

    var body: some View {
        List {
            Section(NSLocalizedString("現在の状態", comment: "")) {
                SyncStatusBadge(state: syncMonitor.syncState)
                Text(syncMonitor.accountState.localizedMessage).font(.caption).foregroundColor(.secondary)
            }

            if let error = loadFailure.lastError {
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
                Button { shareDiagnostics() } label: {
                    Label(NSLocalizedString("診断ログを共有", comment: ""), systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text(NSLocalizedString("診断ログには製品名やメモは含まれません。", comment: "")).font(.caption2)
            }
        }
        .navigationTitle(NSLocalizedString("診断", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
    }

    private func shareDiagnostics() {
        var lines: [String] = []
        lines.append("タナミル (ProjectStock) Diagnostics")
        lines.append("Version: \(AppConfig.marketingVersion) (\(AppConfig.buildNumber))")
        lines.append("CloudKit: \(container.persistence.cloudKitEnabled)")
        lines.append("Account: \(syncMonitor.accountState)")
        lines.append("SyncState: \(syncMonitor.syncState.localizedTitle)")
        lines.append("Device: \(DeviceIdentity.shared.deviceID)")
        lines.append("--- events ---")
        for entry in syncMonitor.recentEvents {
            lines.append("\(DateFormatters.dateTime.string(from: entry.date)) \(entry.typeDescription) \(entry.succeeded ? "OK" : "FAIL") \(entry.message)")
        }
        let text = lines.joined(separator: "\n")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(NSLocalizedString("タナミル_診断ログ", comment: ""))_\(QRExportService.dateStamp()).txt")
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
