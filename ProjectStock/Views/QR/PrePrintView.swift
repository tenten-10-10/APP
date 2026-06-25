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
    @State private var showCaption = true
    @State private var showCutGuides = true
    @State private var shareItem: ShareableFile?
    @State private var error: PresentableError?
    @State private var working = false

    var body: some View {
        NavigationView {
            Form {
                Section(NSLocalizedString("枚数", comment: "")) {
                    Stepper(value: $count, in: 1...200, step: 1) {
                        Text(String(format: NSLocalizedString("%d 枚の空QRを作成", comment: ""), Int(count)))
                    }
                }
                Section(NSLocalizedString("レイアウト", comment: "")) {
                    HStack {
                        Text(String(format: NSLocalizedString("ラベルサイズ: %d mm", comment: ""), Int(labelSizeMM)))
                        Spacer()
                    }
                    Slider(value: $labelSizeMM, in: 8...40, step: 1)
                    Picker(NSLocalizedString("用紙", comment: ""), selection: $paper) {
                        Text("A4").tag(PaperSize.a4)
                        Text("Letter").tag(PaperSize.letter)
                    }
                    .pickerStyle(.segmented)
                    Toggle(NSLocalizedString("コードを文字で併記", comment: ""), isOn: $showCaption)
                    Toggle(NSLocalizedString("カットガイドを表示", comment: ""), isOn: $showCutGuides)
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
            .navigationTitle(NSLocalizedString("空QRの先刷り", comment: ""))
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

        var options = LabelSheetOptions()
        options.labelSizeMM = labelSizeMM
        options.paper = paper
        options.showCaption = showCaption
        options.showCutGuides = showCutGuides

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
