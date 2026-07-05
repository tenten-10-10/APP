import SwiftUI
import CoreData

/// Pick a project to start a stocktake session (spec §11).
struct StocktakeStartView: View {
    @EnvironmentObject private var container: ServiceContainer
    // Entity-NAME-based request (see HomeView): the `sortDescriptors:` convenience
    // form resolves via NSManagedObject.entity(), which returns nil under CloudKit
    // mirroring and crashes SwiftUI with "A fetch request must have an entity."
    @FetchRequest(fetchRequest: {
        let r = Project.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Project.updatedAt, ascending: false)]
        return r
    }()) private var projects: FetchedResults<Project>

    var body: some View {
        List {
            Section {
                Text(NSLocalizedString("連続スキャンで現物を数え、期待在庫との差分を確認して確定します。", comment: ""))
                    .font(.footnote).foregroundColor(.secondary)
            }
            ForEach(projects.filter { !$0.isArchived && container.sharing.canEdit($0) }) { project in
                NavigationLink(destination: StocktakeView(project: project)) {
                    Label(project.displayName, systemImage: "list.clipboard")
                }
            }
        }
        .navigationTitle(NSLocalizedString("棚卸し", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Active stocktake: continuous scanning + running counts (spec §11).
struct StocktakeView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var stocktake: StocktakeCoordinator
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var project: Project

    @State private var torchOn = false
    @State private var zoom: CGFloat = 1
    @State private var message: String?
    @State private var error: PresentableError?

    var body: some View {
        VStack(spacing: 0) {
            ScannerView(torchOn: $torchOn, zoom: $zoom, continuous: true,
                        onScan: handleScan, onError: { _ in })
                .frame(height: 240)
                .overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.8), lineWidth: 2)
                        .frame(width: 150, height: 150)
                )

            if let message {
                Text(message).font(.caption).foregroundColor(.secondary).padding(.vertical, 4)
            }

            List {
                Section {
                    HStack {
                        MetricView(title: NSLocalizedString("スキャン", comment: ""), value: "\(stocktake.session?.scanTotal ?? 0)")
                        MetricView(title: NSLocalizedString("差分あり", comment: ""), value: "\(stocktake.discrepancyCount)")
                        Spacer()
                    }
                }
                Section(NSLocalizedString("カウント", comment: "")) {
                    if stocktake.lines.isEmpty {
                        Text(NSLocalizedString("まだスキャンされていません", comment: "")).foregroundColor(.secondary)
                    }
                    ForEach(stocktake.lines) { line in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(line.productName)
                                Text(String(format: NSLocalizedString("期待 %@ / 実数 %@", comment: ""),
                                            line.expected.quantityString, line.counted.quantityString))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if abs(line.delta) > 0.0001 {
                                Text((line.delta > 0 ? "+" : "") + line.delta.quantityString)
                                    .foregroundColor(line.delta > 0 ? .green : .red).monospacedDigit()
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle(NSLocalizedString("棚卸し", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                // Enabled even with zero discrepancies: counting everything and
                // finding it all correct is the GOOD outcome, and it deserves a
                // positive exit (confirm() applies 0 adjustments and ends the
                // session). Requiring a discrepancy left 中止 as the only way
                // out of a perfect stocktake, which read as "discard my work".
                Button(NSLocalizedString("完了", comment: "")) { confirm() }
                    .disabled(!stocktake.isActive)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button(NSLocalizedString("やめる", comment: "")) { stocktake.cancel(); dismiss() }
            }
        }
        .onAppear { if !stocktake.isActive { stocktake.begin(projectID: project.objectID) } }
        .errorAlert($error)
    }

    private func handleScan(_ raw: String) {
        let outcome = container.scanRouter.route(rawValue: raw, in: container.viewContext)
        switch outcome {
        case .known(let alias):
            // The scanner resolves aliases across ALL local projects, so a label
            // from another project must not be counted into this session.
            guard let product = alias.product ?? alias.unit?.product else {
                message = NSLocalizedString("カウント対象ではありません", comment: "")
                return
            }
            guard product.project?.objectID == project.objectID else {
                Haptics.warning()
                message = NSLocalizedString("別のプロジェクトの製品です", comment: "")
                return
            }
            let unitCode = alias.targetType == .unit ? alias.code : nil
            stocktake.record(product: product, unitCode: unitCode)
            Haptics.tap()
            message = String(format: NSLocalizedString("%@ をカウント", comment: ""), product.displayName)
        default:
            Haptics.warning()
            message = NSLocalizedString("この製品はこのプロジェクトにありません", comment: "")
        }
    }

    private func confirm() {
        let actor = settings.effectiveOperatorName
        let result = stocktake.confirm(using: container.persistence, actor: actor)
        switch result {
        case .success(let count):
            message = String(format: NSLocalizedString("%d 件を調整しました", comment: ""), count)
            dismiss()
        case .failure(let err):
            error = PresentableError(err)
        }
    }
}
