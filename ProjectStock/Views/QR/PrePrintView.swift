import SwiftUI

/// Pre-print blank, unassigned QR labels as an A4/Letter sheet (spec §4.2,
/// §7.5). The codes are minted now (so they're reserved and unique) and can be
/// stuck on items in the field, then assigned later by scanning.
struct PrePrintView: View {
    @EnvironmentObject private var container: ServiceContainer
    @Environment(\.dismiss) private var dismiss
    let project: Project

    @State private var count: Double = 12
    @State private var labelSizeMM: Double = 16
    @State private var paper: PaperSize = .a4
    @State private var marginMM: Double = 8
    @State private var spacingMM: Double = 3
    @State private var showCaption = true
    @State private var cutStyle: CutStyle = .cropMarks
    @State private var shareItem: ShareableFile?
    @State private var error: PresentableError?
    @State private var working = false

    /// Trim/registration guide drawn around each label.
    enum CutStyle: String, CaseIterable, Identifiable {
        case cropMarks, border, none
        var id: String { rawValue }
        var title: String {
            switch self {
            case .cropMarks: return NSLocalizedString("トンボ", comment: "")
            case .border:    return NSLocalizedString("枠線", comment: "")
            case .none:      return NSLocalizedString("なし", comment: "")
            }
        }
    }

    /// The sheet geometry currently configured (used for capacity + export).
    private var sheetOptions: LabelSheetOptions {
        var options = LabelSheetOptions()
        options.labelSizeMM = labelSizeMM
        options.paper = paper
        options.marginMM = marginMM
        options.spacingMM = spacingMM
        options.showCaption = showCaption
        options.showCutGuides = (cutStyle == .border)
        options.cropMarks = (cutStyle == .cropMarks)
        return options
    }
    private var capacity: (columns: Int, rows: Int, perPage: Int) { sheetOptions.capacity }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(NSLocalizedString("これは何?", comment: ""), systemImage: "lightbulb.fill")
                            .font(.subheadline.weight(.semibold)).foregroundColor(Brand.primary)
                        Text(NSLocalizedString("サンプルが届く前に、空のQRラベルをまとめて発行できます。サンプルや棚・箱に先に貼っておき、届いたらスキャンして「これは○○」と登録します。", comment: ""))
                            .font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
                Section(NSLocalizedString("枚数", comment: "")) {
                    Stepper(value: $count, in: 1...500, step: 1) {
                        Text(String(format: NSLocalizedString("%d 枚のサンプル用QRを作成", comment: ""), Int(count)))
                    }
                    Button {
                        count = Double(capacity.perPage)
                    } label: {
                        Label(String(format: NSLocalizedString("A4いっぱいに敷き詰める（%d枚）", comment: ""), capacity.perPage),
                              systemImage: "square.grid.3x3.fill")
                    }
                    .accessibilityIdentifier("fillPageButton")
                } footer: {
                    Text(String(format: NSLocalizedString("この設定だと1ページに %d 枚（%d×%d）並びます。%d 枚だと %d ページになります。", comment: ""),
                                capacity.perPage, capacity.columns, capacity.rows,
                                Int(count), max(1, Int(ceil(count / Double(capacity.perPage))))))
                        .font(.caption2)
                }
                Section(NSLocalizedString("レイアウト", comment: "")) {
                    Picker(NSLocalizedString("用紙", comment: ""), selection: $paper) {
                        Text("A4").tag(PaperSize.a4)
                        Text("Letter").tag(PaperSize.letter)
                    }
                    .pickerStyle(.segmented)
                    VStack(alignment: .leading) {
                        Text(String(format: NSLocalizedString("ラベルサイズ: %d mm", comment: ""), Int(labelSizeMM)))
                        Slider(value: $labelSizeMM, in: 8...40, step: 1)
                    }
                    Picker(NSLocalizedString("切り取り線", comment: ""), selection: $cutStyle) {
                        ForEach(CutStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle(NSLocalizedString("コードを文字で併記", comment: ""), isOn: $showCaption)
                }
                Section(NSLocalizedString("ラベルシート調整", comment: "")) {
                    VStack(alignment: .leading) {
                        Text(String(format: NSLocalizedString("外側の余白: %d mm", comment: ""), Int(marginMM)))
                        Slider(value: $marginMM, in: 0...25, step: 1)
                    }
                    VStack(alignment: .leading) {
                        Text(String(format: NSLocalizedString("ラベル間隔: %d mm", comment: ""), Int(spacingMM)))
                        Slider(value: $spacingMM, in: 0...20, step: 1)
                    }
                } footer: {
                    Text(NSLocalizedString("お使いのラベルシートに合わせて、余白・間隔・ラベルサイズを調整してください。トンボを目印に貼り付け・カットできます。", comment: ""))
                        .font(.caption2)
                }
                Section {
                    Button {
                        generate()
                    } label: {
                        if working { ProgressView() }
                        else { Label(NSLocalizedString("作成して書き出す", comment: ""), systemImage: "printer") }
                    }
                    .disabled(working)
                    .accessibilityIdentifier("prePrintGenerate")
                } footer: {
                    Text(NSLocalizedString("ここで作成したコードは一意に予約されます。現場で貼り、スキャンして製品・個体・場所へ後から割り当てられます。", comment: ""))
                        .font(.caption2)
                }
            }
            .navigationTitle(NSLocalizedString("サンプル用QRをまとめて発行", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(NSLocalizedString("閉じる", comment: "")) { dismiss() } } }
            .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
            .errorAlert($error)
        }
    }

    private func generate() {
        working = true
        let projectID = project.objectID
        let n = Int(count)
        var codes: [String] = []
        let writeResult = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: projectID) as? Project else { return }
            let aliases = try container.aliases.createUnassignedBatch(count: n, in: p, context: ctx)
            codes = aliases.map { $0.code }
        }
        if case .failure(let err) = writeResult { working = false; error = PresentableError(err); return }

        let options = sheetOptions
        let entries: [(code: String, caption: String?)] = codes.map { (code: $0, caption: showCaption ? $0 : nil) }
        let exportContext = QRExportService.ExportContext(projectName: project.displayName, targetName: "blank")
        do {
            let url = try container.qrExport.exportLabelSheet(codes: entries, options: options, context: exportContext)
            shareItem = ShareableFile(url: url)
        } catch {
            self.error = PresentableError(error)
        }
        working = false
    }
}
