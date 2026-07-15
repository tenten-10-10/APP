import SwiftUI

// MARK: - ExportView

/// ネームを PDF に書き出す画面。PDF 書き出しは Plus 以上の機能。
struct ExportView: View {

    @Environment(ProjectStore.self) private var store
    @Environment(BillingService.self) private var billing

    @State private var exportedURL: URL?
    @State private var isExporting = false
    @State private var errorMessage: String?
    @State private var showShareSheet = false

    private var bundle: ProjectBundle? { store.selectedBundle }

    var body: some View {
        Form {
            if let bundle {
                Section("対象") {
                    LabeledContent("タイトル", value: bundle.project.title)
                    LabeledContent("ページ数", value: "\(bundle.pagePlans.count)")
                    LabeledContent("コマ総数", value: "\(bundle.panels.count)")
                }

                Section {
                    Button {
                        exportPDF(bundle: bundle)
                    } label: {
                        HStack {
                            Label("PDFを書き出す", systemImage: "doc.richtext")
                            Spacer()
                            if isExporting { ProgressView() }
                        }
                    }
                    .disabled(isExporting)
                } footer: {
                    Text("表紙＋全ページのコマ割り・セリフを PDF 化します（PDFKit）。")
                }

                if let url = exportedURL {
                    Section("書き出し済み") {
                        Button {
                            showShareSheet = true
                        } label: {
                            Label("共有 / 保存", systemImage: "square.and.arrow.up")
                        }
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "xmark.octagon")
                            .foregroundStyle(.red)
                    }
                }
            } else {
                ContentUnavailableView(
                    "プロジェクト未選択",
                    systemImage: "doc",
                    description: Text("書き出すプロジェクトを選んでください。")
                )
            }
        }
        .navigationTitle("書き出し")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func exportPDF(bundle: ProjectBundle) {
        // PDF 書き出しは Plus 以上。
        guard billing.requireFeature(.pdfExport) else { return }

        isExporting = true
        errorMessage = nil
        // PDF 生成は同期だが UI を固めないよう少し後段で実行。
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try PDFExporter.export(bundle: bundle)
                DispatchQueue.main.async {
                    exportedURL = url
                    isExporting = false
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }
}

// MARK: - ShareSheet

/// UIActivityViewController のラッパー。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        ExportView()
    }
    .environmentForPreview()
}
