import SwiftUI

/// Assigns a freshly-scanned unassigned label to a target (spec §4.2): a new or
/// existing product, an individual unit, or a location/container.
struct AssignmentView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var alias: CodeAlias

    @State private var assignedSummary: String?
    @State private var error: PresentableError?

    private var project: Project? { alias.project }
    private var canEdit: Bool { project.map { container.sharing.canEdit($0) } ?? false }

    var body: some View {
        List {
            Section {
                Label(alias.code, systemImage: "qrcode")
                Text(NSLocalizedString("このラベルはまだ割り当てられていません。割当先を選んでください。", comment: ""))
                    .font(.footnote).foregroundColor(.secondary)
            }

            if let summary = assignedSummary {
                Section { Label(summary, systemImage: "checkmark.circle").foregroundColor(.green) }
            } else if !canEdit {
                Section { Text(NSLocalizedString("このプロジェクトは読み取り専用のため割り当てできません。", comment: "")).foregroundColor(.secondary) }
            } else if let project {
                Section(NSLocalizedString("割当先", comment: "")) {
                    NavigationLink {
                        NewProductAssignView(alias: alias, project: project) { summary in assignedSummary = summary }
                    } label: { Label(NSLocalizedString("新規製品を作成して割り当て", comment: ""), systemImage: "plus.app") }
                        .accessibilityIdentifier("assignNewProduct")

                    NavigationLink {
                        ExistingTargetPicker(title: NSLocalizedString("製品を選択", comment: ""), items: project.productArray.filter { !$0.isArchived },
                                             label: { $0.displayName }) { product in assign(.product(product)) }
                    } label: { Label(NSLocalizedString("既存の製品へ割り当て", comment: ""), systemImage: "shippingbox") }

                    NavigationLink {
                        ExistingTargetPicker(title: NSLocalizedString("個体を選択", comment: ""), items: allUnits(in: project),
                                             label: { "\($0.displaySerial) (\($0.product?.displayName ?? ""))" }) { unit in assign(.unit(unit)) }
                    } label: { Label(NSLocalizedString("個体へ割り当て", comment: ""), systemImage: "number") }

                    NavigationLink {
                        ExistingTargetPicker(title: NSLocalizedString("場所を選択", comment: ""), items: project.locationArray,
                                             label: { $0.breadcrumb }) { location in assign(.location(location)) }
                    } label: { Label(NSLocalizedString("保管場所・コンテナへ割り当て", comment: ""), systemImage: "tray.full") }
                }
            }
        }
        .navigationTitle(NSLocalizedString("ラベルを割り当て", comment: ""))
        .errorAlert($error)
    }

    private func allUnits(in project: Project) -> [StockUnit] {
        project.productArray.flatMap { $0.unitArray }
    }

    private func assign(_ target: CodeAliasService.AliasTarget) {
        let aliasID = alias.objectID
        let targetID: NSManagedObjectID
        switch target {
        case .product(let p): targetID = p.objectID
        case .unit(let u): targetID = u.objectID
        case .location(let l): targetID = l.objectID
        }
        let result = container.performWrite { ctx in
            guard let a = try ctx.existingObject(with: aliasID) as? CodeAlias else { return }
            let resolved: CodeAliasService.AliasTarget
            switch target {
            case .product: resolved = .product(try ctx.existingObject(with: targetID) as! Product)
            case .unit:    resolved = .unit(try ctx.existingObject(with: targetID) as! StockUnit)
            case .location: resolved = .location(try ctx.existingObject(with: targetID) as! Location)
            }
            try container.aliases.assign(alias: a, to: resolved)
        }
        switch result {
        case .success: assignedSummary = String(format: NSLocalizedString("%@ に割り当てました", comment: ""), alias.resolvedTargetName)
        case .failure(let err): error = PresentableError(err)
        }
    }
}

/// Generic picker over project objects to assign to.
private struct ExistingTargetPicker<Item: NSManagedObject & Identifiable>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let items: [Item]
    let label: (Item) -> String
    let onSelect: (Item) -> Void

    var body: some View {
        List {
            if items.isEmpty {
                Text(NSLocalizedString("候補がありません", comment: "")).foregroundColor(.secondary)
            }
            ForEach(items) { item in
                Button { onSelect(item); dismiss() } label: {
                    HStack { Text(label(item)); Spacer() }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Inline new-product creation that immediately binds the scanned label.
private struct NewProductAssignView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var alias: CodeAlias
    let project: Project
    let onAssigned: (String) -> Void

    @State private var name = ""
    @State private var unitName = "pcs"
    @State private var mode: TrackingMode = .quantity
    @State private var error: PresentableError?

    var body: some View {
        Form {
            Section(NSLocalizedString("新規製品", comment: "")) {
                TextField(NSLocalizedString("製品名", comment: ""), text: $name)
                    .accessibilityIdentifier("assignProductNameField")
                TextField(NSLocalizedString("単位", comment: ""), text: $unitName)
                Picker(NSLocalizedString("追跡モード", comment: ""), selection: $mode) {
                    ForEach(TrackingMode.allCases) { Text($0.localizedTitle).tag($0) }
                }
            }
            Section {
                Button(NSLocalizedString("作成して割り当て", comment: "")) { create() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle(NSLocalizedString("新規製品", comment: ""))
        .errorAlert($error)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = unitName.trimmingCharacters(in: .whitespaces)
        let chosenMode = mode
        let aliasID = alias.objectID
        let projectID = project.objectID
        let result = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: projectID) as? Project,
                  let a = try ctx.existingObject(with: aliasID) as? CodeAlias else { return }
            let product = Product.make(in: ctx, name: trimmed, project: p, unitName: unit.isEmpty ? "pcs" : unit, trackingMode: chosenMode)
            container.router.assignChild(product, toSameStoreAs: p, in: ctx)
            try container.aliases.assign(alias: a, to: .product(product))
        }
        switch result {
        case .success:
            onAssigned(String(format: NSLocalizedString("%@ を作成して割り当てました", comment: ""), trimmed))
            dismiss()
        case .failure(let err): error = PresentableError(err)
        }
    }
}
