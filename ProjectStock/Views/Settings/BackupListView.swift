import SwiftUI

/// 設定 > バックアップ。毎日の自動スナップショットの一覧と、手動バックアップ・
/// 書き出し・復元。復元は必ず「新しいプロジェクトとして追加」で、既存データには
/// 一切触らない（共有・同期トラブルからの復旧手段。spec: BackupService）。
struct BackupListView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings

    @State private var files: [BackupService.BackupFile] = []
    @State private var restoringFile: BackupService.BackupFile?
    @State private var sharingFile: BackupService.BackupFile?
    @State private var working = false
    @State private var info: String?
    @State private var error: PresentableError?

    var body: some View {
        List {
            Section {
                Button {
                    backupNow()
                } label: {
                    Label(NSLocalizedString("今すぐバックアップ", comment: ""), systemImage: "arrow.down.doc")
                }
                .disabled(working)
            } footer: {
                Text(NSLocalizedString("アプリ起動時に1日1回、自動でこの端末内にバックアップされます（最新14件を保持）。プロジェクト構成・在庫数・個体・ロット・QRコード・貸出中の情報が対象です（写真と操作履歴は含まれません）。", comment: ""))
            }

            Section(NSLocalizedString("保存済みバックアップ", comment: "")) {
                if files.isEmpty {
                    Text(NSLocalizedString("バックアップはまだありません", comment: ""))
                        .foregroundColor(.secondary)
                }
                ForEach(files) { file in
                    Button {
                        restoringFile = file
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(DateFormatters.dateTime.string(from: file.createdAt))
                                Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            container.backups.deleteBackup(at: file.url)
                            reload()
                        } label: {
                            Label(NSLocalizedString("削除", comment: ""), systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("バックアップ", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .confirmationDialog(
            restoringFile.map { DateFormatters.dateTime.string(from: $0.createdAt) } ?? "",
            isPresented: Binding(get: { restoringFile != nil },
                                 set: { if !$0 { restoringFile = nil } }),
            titleVisibility: .visible,
            presenting: restoringFile
        ) { file in
            Button(NSLocalizedString("新しいプロジェクトとして復元", comment: "")) { restore(file) }
            Button(NSLocalizedString("ファイルを書き出す", comment: "")) { sharingFile = file }
            Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) { restoringFile = nil }
        } message: { _ in
            Text(NSLocalizedString("復元は既存のデータを変更しません。バックアップ内の各プロジェクトが「◯◯（復元）」として追加されます。", comment: ""))
        }
        .sheet(item: $sharingFile) { file in
            ShareSheet(items: [file.url])
        }
        .alert(NSLocalizedString("完了", comment: ""),
               isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) {
            Button("OK") { info = nil }
        } message: {
            Text(info ?? "")
        }
        .errorAlert($error)
    }

    private func reload() {
        files = container.backups.listBackups()
    }

    private func backupNow() {
        working = true
        defer { working = false }
        switch container.createBackupNow() {
        case .success:
            Haptics.success()
            reload()
            info = NSLocalizedString("バックアップを保存しました", comment: "")
        case .failure(let err):
            error = PresentableError(err)
        }
    }

    private func restore(_ file: BackupService.BackupFile) {
        working = true
        defer { working = false }
        switch container.restoreBackup(from: file.url, actor: settings.effectiveOperatorName) {
        case .success:
            Haptics.success()
            info = NSLocalizedString("復元しました。プロジェクト一覧に「（復元）」付きで追加されています。", comment: "")
        case .failure(let err):
            error = PresentableError(err)
        }
        restoringFile = nil
    }
}
