import CoreData
import SwiftUI

/// Assigns a freshly-scanned unassigned label to a target (spec §4.2): a new or
/// existing product, an individual unit, or a location/container.
struct AssignmentView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
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
                Section {
                    Label(summary, systemImage: "checkmark.circle").foregroundColor(.green)
                    // Field setup means registering dozens of items in a row —
                    // give a one-tap path back to the scanner instead of making
                    // the user hunt for the 閉じる button every time.
                    Button {
                        dismiss()
                    } label: {
                        Label(NSLocalizedString("続けて次のQRをスキャン", comment: ""), systemImage: "qrcode.viewfinder")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityIdentifier("continueScanning")
                    // 割当先を取り違えた直後の復帰路。以前は誤割当を戻す手段が
                    // なく、貼った現物と登録がズレたまま運用が始まってしまった。
                    Button {
                        undoAssignment()
                    } label: {
                        Label(NSLocalizedString("割り当てをやり直す", comment: ""), systemImage: "arrow.uturn.backward")
                            .foregroundColor(.orange)
                    }
                }
            } else if !canEdit {
                Section { Text(NSLocalizedString("このプロジェクトは読み取り専用のため割り当てできません。", comment: "")).foregroundColor(.secondary) }
            } else if let project {
                Section(NSLocalizedString("割当先", comment: "")) {
                    NavigationLink {
                        NewProductAssignView(alias: alias, project: project) { summary in assignedSummary = summary }
                    } label: {
                        Label(NSLocalizedString("このQRに品物を登録", comment: ""), systemImage: "plus.app.fill")
                            .font(.body.weight(.semibold))
                            .foregroundColor(Brand.primary)
                    }
                    .accessibilityIdentifier("assignNewProduct")
                }

                Section(NSLocalizedString("または既存へ割り当て", comment: "")) {
                    // 「同じ製品の2点目以降」の動線: 製品を選ぶと新しい個体を
                    // 作って登録し、QRをその個体にひも付ける。従来はQRを製品に
                    // 付けるか、先に個体を手作りしておくしかなかった。
                    NavigationLink {
                        ExistingTargetPicker(title: NSLocalizedString("製品を選択", comment: ""),
                                             items: project.productArray.filter { !$0.isArchived && $0.trackingMode == .individual },
                                             label: { $0.displayName }) { product in addUnitAndAssign(to: product) }
                    } label: { Label(NSLocalizedString("既存の製品に個体を追加", comment: ""), systemImage: "plus.square.on.square") }

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
        .keyboardDoneBar()
        .errorAlert($error)
    }

    private func allUnits(in project: Project) -> [StockUnit] {
        project.productArray.flatMap { $0.unitArray }
    }

    /// Release the just-made assignment and show the target picker again.
    private func undoAssignment() {
        let aliasID = alias.objectID
        let result = container.performWrite { ctx in
            guard let a = try ctx.existingObject(with: aliasID) as? CodeAlias else { return }
            container.aliases.unassign(alias: a)
        }
        switch result {
        case .success:
            Haptics.success()
            assignedSummary = nil
        case .failure(let err):
            error = PresentableError(err)
        }
    }

    /// Create a NEW unit under an existing individual-tracked product, register
    /// it in the ledger, and bind the scanned label to that unit.
    private func addUnitAndAssign(to product: Product) {
        let aliasID = alias.objectID
        let productID = product.objectID
        let actor = settings.effectiveOperatorName
        var summary = ""
        let result = container.performWrite { ctx in
            guard let a = try ctx.existingObject(with: aliasID) as? CodeAlias,
                  let p = try ctx.existingObject(with: productID) as? Product,
                  let proj = p.project else { return }
            let serial = "#\(p.unitArray.count + 1)"
            let unit = StockUnit.make(in: ctx, serialNumber: serial, product: p,
                                      project: proj, location: p.defaultLocation)
            container.router.assignChild(unit, toSameStoreAs: proj, in: ctx)
            container.inventory.registerUnit(unit, location: p.defaultLocation, actor: actor, in: ctx)
            try container.aliases.assign(alias: a, to: .unit(unit))
            summary = String(format: NSLocalizedString("%@ の個体 %@ を追加してひも付けました", comment: ""),
                             p.displayName, serial)
        }
        switch result {
        case .success:
            Haptics.success()
            assignedSummary = summary
        case .failure(let err):
            error = PresentableError(err)
        }
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
///
/// 既定は「個体管理」: 現物1点にQRを貼る使い方が主流のため。個体管理で登録
/// すると製品と一緒に個体(StockUnit)を1つ作り、**QRはその個体にひも付く** —
/// 以前は追跡モードで個体を選んでもラベルが製品側に付き、貸出・返却が
/// スキャンから使えなかった（「個体管理に使えない」問題の真因）。
/// あわせてフォルダ・保管場所をここで選び、その場所へ直接登録できる。
private struct NewProductAssignView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var alias: CodeAlias
    let project: Project
    let onAssigned: (String) -> Void

    @State private var name = ""
    @State private var unitName = NSLocalizedString("個", comment: "default unit")
    @State private var mode: TrackingMode = .individual
    @State private var folderID: NSManagedObjectID?
    @State private var locationID: NSManagedObjectID?
    @State private var error: PresentableError?

    var body: some View {
        Form {
            Section {
                TextField(NSLocalizedString("品物の名前", comment: ""), text: $name)
                    .accessibilityIdentifier("assignProductNameField")
                Picker(NSLocalizedString("管理方法", comment: ""), selection: $mode) {
                    ForEach(TrackingMode.allCases) { Text($0.localizedTitle).tag($0) }
                }
                if mode == .quantity {
                    TextField(NSLocalizedString("単位", comment: ""), text: $unitName)
                }
            } header: {
                Text(NSLocalizedString("新規登録", comment: ""))
            } footer: {
                Text(modeFooter)
            }
            Section(NSLocalizedString("登録先（任意）", comment: "")) {
                folderPicker
                locationPicker
            }
            Section {
                Button(createButtonTitle) { create() }
                    .font(.body.weight(.semibold))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle(NSLocalizedString("このQRに品物を登録", comment: ""))
        .keyboardDoneBar()
        .errorAlert($error)
    }

    private var modeFooter: String {
        switch mode {
        case .individual:
            return NSLocalizedString("この1点をQRで管理します。QRはこの個体にひも付き、スキャンから貸出・返却できます。", comment: "")
        case .quantity:
            return NSLocalizedString("まとめて数量で管理します。QRは製品にひも付き、スキャンから入庫・出庫できます。", comment: "")
        case .lot:
            return NSLocalizedString("ロット（製造単位）ごとに管理します。ロットは製品画面から追加します。", comment: "")
        }
    }

    private var createButtonTitle: String {
        mode == .individual
            ? NSLocalizedString("個体として登録してQRをひも付け", comment: "")
            : NSLocalizedString("作成して割り当て", comment: "")
    }

    private var folderPicker: some View {
        Picker(NSLocalizedString("フォルダ", comment: ""), selection: $folderID) {
            Text(NSLocalizedString("なし", comment: "")).tag(NSManagedObjectID?.none)
            ForEach(project.folderArray) { folder in
                Text(folder.displayName).tag(Optional(folder.objectID))
            }
        }
    }

    private var locationPicker: some View {
        Picker(NSLocalizedString("保管場所", comment: ""), selection: $locationID) {
            Text(NSLocalizedString("なし", comment: "")).tag(NSManagedObjectID?.none)
            ForEach(project.locationArray) { location in
                Text(location.breadcrumb).tag(Optional(location.objectID))
            }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = unitName.trimmingCharacters(in: .whitespaces)
        let chosenMode = mode
        let aliasID = alias.objectID
        let projectID = project.objectID
        let folderOID = folderID
        let locationOID = locationID
        let actor = settings.effectiveOperatorName
        let result = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: projectID) as? Project,
                  let a = try ctx.existingObject(with: aliasID) as? CodeAlias else { return }
            let folder = try folderOID.map { try ctx.existingObject(with: $0) as? Folder } ?? nil
            let location = try locationOID.map { try ctx.existingObject(with: $0) as? Location } ?? nil
            let product = Product.make(in: ctx, name: trimmed, project: p,
                                       unitName: unit.isEmpty ? NSLocalizedString("個", comment: "") : unit,
                                       trackingMode: chosenMode, folder: folder)
            product.defaultLocation = location
            container.router.assignChild(product, toSameStoreAs: p, in: ctx)
            if chosenMode == .individual {
                // 個体を作って登録し、QRを個体そのものにひも付ける。
                let stockUnit = StockUnit.make(in: ctx, serialNumber: "#1", product: product,
                                               project: p, location: location)
                container.router.assignChild(stockUnit, toSameStoreAs: p, in: ctx)
                container.inventory.registerUnit(stockUnit, location: location, actor: actor, in: ctx)
                try container.aliases.assign(alias: a, to: .unit(stockUnit))
            } else {
                try container.aliases.assign(alias: a, to: .product(product))
            }
        }
        switch result {
        case .success:
            let format = chosenMode == .individual
                ? NSLocalizedString("%@ を個体として登録し、QRをひも付けました", comment: "")
                : NSLocalizedString("%@ を作成して割り当てました", comment: "")
            onAssigned(String(format: format, trimmed))
            dismiss()
        case .failure(let err): error = PresentableError(err)
        }
    }
}
