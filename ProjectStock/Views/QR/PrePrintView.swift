import SwiftUI

/// Pre-print blank, unassigned QR labels as an A4/Letter sheet (spec §4.2,
/// §7.5). The codes are minted now (so they're reserved and unique) and can be
/// stuck on items in the field, then assigned later by scanning.
struct PrePrintView: View {
    @EnvironmentObject private var container: ServiceContainer
    @Environment(\.dismiss) private var dismiss
    let project: Project

    /// Number of DISTINCT codes to mint (種類). Every label is unique by
    /// default — the sample workflow wants one QR per physical item.
    @State private var count: Double = 12
    /// Copies printed of each code (部数). Kept at 1 for samples; raised when
    /// several stickers of the SAME code are wanted (e.g. boxes of one lot).
    @State private var copies: Double = 1
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

    /// How many distinct codes the fill-the-page button should mint so that
    /// 種類 × 部数 fits one page (120 slots / 10 copies → 12 kinds).
    private var fillCounts: (kinds: Int, total: Int) {
        let copiesEach = max(1, Int(copies))
        let kinds = max(1, capacity.perPage / copiesEach)
        return (kinds, kinds * copiesEach)
    }

    private var capacityFooter: String {
        let cap = capacity
        let kinds = Int(count)
        let copiesEach = Int(copies)
        let total = kinds * copiesEach
        let pages = max(1, Int((Double(total) / Double(cap.perPage)).rounded(.up)))
        if copiesEach == 1 {
            return String(format: NSLocalizedString("この設定だと1ページに %d 枚（%d×%d）並びます。%d 枚はすべて別々のQRです（%d ページ）。同じQRを複数枚（同じロットの箱に貼るなど）にしたい場合は「同じQRを◯枚ずつ」を増やせます。", comment: ""),
                          cap.perPage, cap.columns, cap.rows, total, pages)
        } else {
            return String(format: NSLocalizedString("この設定だと1ページに %d 枚（%d×%d）並びます。%d 種類 × %d 枚ずつ = 合計 %d 枚（%d ページ）。同じQRは隣どうしに並びます。", comment: ""),
                          cap.perPage, cap.columns, cap.rows, kinds, copiesEach, total, pages)
        }
    }

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
                Section {
                    Stepper(value: $count, in: 1...500, step: 1) {
                        Text(String(format: NSLocalizedString("%d 種類のQRを作成", comment: ""), Int(count)))
                    }
                    Stepper(value: $copies, in: 1...20, step: 1) {
                        Text(String(format: NSLocalizedString("同じQRを %d 枚ずつ", comment: ""), Int(copies)))
                    }
                    .accessibilityIdentifier("copiesStepper")
                    Button {
                        count = Double(fillCounts.kinds)
                    } label: {
                        Label(String(format: NSLocalizedString("%@いっぱいに敷き詰める（合計 %d 枚）", comment: ""),
                                     paper.localizedTitle, fillCounts.total),
                              systemImage: "square.grid.3x3.fill")
                    }
                    .accessibilityIdentifier("fillPageButton")
                } header: {
                    Text(NSLocalizedString("枚数", comment: ""))
                } footer: {
                    Text(capacityFooter).font(.caption2)
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
                Section {
                    VStack(alignment: .leading) {
                        Text(String(format: NSLocalizedString("外側の余白: %d mm", comment: ""), Int(marginMM)))
                        Slider(value: $marginMM, in: 0...25, step: 1)
                    }
                    VStack(alignment: .leading) {
                        Text(String(format: NSLocalizedString("ラベル間隔: %d mm", comment: ""), Int(spacingMM)))
                        Slider(value: $spacingMM, in: 0...20, step: 1)
                    }
                } header: {
                    Text(NSLocalizedString("ラベルシート調整", comment: ""))
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
        let kinds = Int(count)
        let copiesEach = max(1, Int(copies))
        var codes: [String] = []
        let writeResult = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: projectID) as? Project else { return }
            let aliases = try container.aliases.createUnassignedBatch(count: kinds, in: p, context: ctx)
            codes = aliases.map { $0.code }
        }
        if case .failure(let err) = writeResult { working = false; error = PresentableError(err); return }

        let options = sheetOptions
        // Copies of the same code are laid out consecutively so they sit next
        // to each other on the sheet and are easy to cut as a group.
        let entries: [(code: String, caption: String?)] = codes.flatMap { code in
            Array(repeating: (code: code, caption: showCaption ? code : nil), count: copiesEach)
        }
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
