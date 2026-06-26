import SwiftUI

/// QR Label Studio (spec §12.5): preview, size/format/DPI/ECC/background
/// controls, scanability score, export to PNG/PDF/EPS/SVG, calibration sheet,
/// and Share Sheet / Files saving.
struct QRLabelStudioView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model: QRStudioViewModel

    let projectName: String
    let targetName: String

    @State private var shareItem: ShareableFile?
    @State private var mailItem: ShareableFile?
    @State private var showAdvanced = false
    @State private var error: PresentableError?

    init(code: String, projectName: String, targetName: String) {
        self.projectName = projectName
        self.targetName = targetName
        _model = StateObject(wrappedValue: QRStudioViewModel(code: code, settings: AppSettings.shared))
    }

    var body: some View {
        List {
            previewSection
            sizeSection
            exportSection
            advancedSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("QRラベル", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
        .sheet(item: $mailItem) { item in
            MailComposeView(
                subject: String(format: NSLocalizedString("QRラベル: %@ / %@", comment: ""), projectName, targetName),
                body: NSLocalizedString("QRラベルを添付します。印刷してご利用ください。", comment: ""),
                attachmentURL: item.url
            )
        }
        .errorAlert($error)
    }

    private var previewSection: some View {
        Section {
            VStack(spacing: 8) {
                if let image = model.previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .padding(8)
                        .background(checkerboard)
                        .accessibilityLabel(Text(String(format: NSLocalizedString("コード %@ のQRプレビュー", comment: ""), model.code)))
                } else if let err = model.encodeError {
                    Text(err).foregroundColor(.red)
                } else {
                    ProgressView()
                }
                Text(model.code).font(.system(.footnote, design: .monospaced)).foregroundColor(.secondary)
            }
        }
    }

    /// Power-user controls collapsed by default so the common flow stays simple.
    /// The readability chip stays visible on the row so anyone gets a go/no-go
    /// signal without opening it.
    private var advancedSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showAdvanced) {
                Picker(NSLocalizedString("誤り訂正", comment: ""), selection: $model.errorCorrection) {
                    ForEach(QRErrorCorrectionLevel.allCases) { Text($0.localizedTitle).tag($0) }
                }
                Picker(NSLocalizedString("DPI", comment: ""), selection: $model.dpi) {
                    ForEach([300, 600, 1200], id: \.self) { Text("\($0)").tag($0) }
                }
                Picker(NSLocalizedString("背景", comment: ""), selection: $model.background) {
                    ForEach(QRBackgroundMode.allCases) { Text($0.localizedTitle).tag($0) }
                }
                if model.background == .fullyTransparent {
                    Label(NSLocalizedString("余白まで透過すると、背景によっては読み取れません。", comment: ""), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundColor(.orange)
                }
                if let report = model.report {
                    LabeledRow(title: NSLocalizedString("1モジュール", comment: ""),
                               value: String(format: "%.3f mm (%.1f px)", report.moduleSizeMM, report.modulePixels))
                    LabeledRow(title: NSLocalizedString("Quiet Zone", comment: ""),
                               value: String(format: "%d モジュール (%.2f mm)", report.quietZoneModules, report.quietZoneMM))
                    LabeledRow(title: NSLocalizedString("誤り訂正 / DPI", comment: ""),
                               value: "\(report.errorCorrection.rawValue) / \(report.dpi)")
                    Text("v\(report.version) · \(report.dataModuleCount)×\(report.dataModuleCount)")
                        .font(.caption).foregroundColor(.secondary)
                    ForEach(report.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "info.circle")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            } label: {
                HStack {
                    Label(NSLocalizedString("詳細設定", comment: ""), systemImage: "slider.horizontal.3")
                    Spacer()
                    if let report = model.report { ScanabilityChip(rating: report.rating) }
                }
            }
        } footer: {
            Text(NSLocalizedString("誤り訂正・解像度・背景・読み取り評価などの詳細です。通常は変更不要です。", comment: ""))
                .font(.caption2)
        }
    }

    private var sizeSection: some View {
        Section(NSLocalizedString("サイズ", comment: "")) {
            Picker(NSLocalizedString("プリセット", comment: ""), selection: $model.sizePreset) {
                ForEach(QRSizePreset.allCases) { Text($0.localizedTitle).tag($0) }
            }
            .pickerStyle(.segmented)

            if model.sizePreset == .custom {
                VStack(alignment: .leading) {
                    Text(String(format: NSLocalizedString("カスタム: %.0f mm", comment: ""), model.customMM))
                    Slider(value: $model.customMM,
                           in: QRSizePreset.customRange.lowerBound...QRSizePreset.customRange.upperBound,
                           step: 1)
                }
            }
            Text(String(format: NSLocalizedString("印刷サイズ（Quiet Zone含む）: 約 %.0f mm", comment: ""), model.totalSizeMM))
                .font(.caption).foregroundColor(.secondary)
            if model.totalSizeMM < 8 {
                Label(NSLocalizedString("8mm未満です。校正シートで実機確認してください。", comment: ""), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundColor(.orange)
            }
        }
    }

    // Error-correction / DPI / background controls live in `advancedSection`.

    private var exportSection: some View {
        Section {
            Picker(NSLocalizedString("形式", comment: ""), selection: $model.format) {
                ForEach(QRExportFormat.allCases) { Text($0.localizedTitle).tag($0) }
            }
            .pickerStyle(.segmented)

            Button {
                exportThenMail()
            } label: {
                Label(NSLocalizedString("メールで送る", comment: ""), systemImage: "envelope.fill")
            }
            .accessibilityIdentifier("emailQRButton")

            Button {
                exportLabel()
            } label: {
                Label(NSLocalizedString("共有・ファイルに保存", comment: ""), systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("exportQRButton")

            Button {
                exportCalibration()
            } label: {
                Label(NSLocalizedString("印刷校正シートを作成", comment: ""), systemImage: "printer")
            }
        } header: {
            Text(NSLocalizedString("書き出し", comment: ""))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("メールに添付したり「ファイル」に保存すると、Windowsパソコンでも開けます。", comment: ""))
                Text(NSLocalizedString("PNGは透過対応、PDFとEPSはベクターです。ファイルは一時領域に作成され、一定時間後に自動削除されます。", comment: ""))
            }
            .font(.caption2)
        }
    }

    private var checkerboard: some View {
        // Visualizes transparency in the preview.
        Color(.secondarySystemBackground)
    }

    private func exportLabel() {
        do {
            let url = try model.export(projectName: projectName, targetName: targetName)
            shareItem = ShareableFile(url: url)
        } catch { self.error = PresentableError(error) }
    }

    private func exportThenMail() {
        do {
            let url = try model.export(projectName: projectName, targetName: targetName)
            // Compose an email directly when Mail is set up; otherwise fall back to
            // the system share sheet (which still offers other mail apps / Files).
            if MailComposeView.canSend {
                mailItem = ShareableFile(url: url)
            } else {
                shareItem = ShareableFile(url: url)
            }
        } catch { self.error = PresentableError(error) }
    }

    private func exportCalibration() {
        do {
            let url = try model.exportCalibrationSheet(projectName: projectName, targetName: targetName)
            shareItem = ShareableFile(url: url)
        } catch { self.error = PresentableError(error) }
    }
}
