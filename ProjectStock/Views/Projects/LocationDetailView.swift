import SwiftUI

/// Location detail with its contents and the container bulk-move action
/// (spec §4.3): move everything in this location to another location.
struct LocationDetailView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var location: Location
    let canEdit: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var showingBulkMove = false
    @State private var showingAddChild = false
    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var retiringLabel: CodeAlias?
    @State private var unassigningLabel: CodeAlias?
    @State private var issuedCode: String?
    @State private var error: PresentableError?
    @State private var moveResult: String?

    var body: some View {
        List {
            Section(NSLocalizedString("情報", comment: "")) {
                LabeledRow(title: NSLocalizedString("種類", comment: ""), value: location.kind.localizedTitle)
                LabeledRow(title: NSLocalizedString("パス", comment: ""), value: location.breadcrumb)
            }

            if !location.childArray.isEmpty {
                Section(NSLocalizedString("サブの場所", comment: "")) {
                    ForEach(location.childArray) { child in
                        NavigationLink(destination: LocationDetailView(location: child, canEdit: canEdit)) {
                            LocationRow(location: child)
                        }
                    }
                }
            }

            Section(NSLocalizedString("製品", comment: "")) {
                let products = location.productArray
                if products.isEmpty {
                    Text(NSLocalizedString("この場所に既定の製品はありません", comment: "")).foregroundColor(.secondary)
                } else {
                    ForEach(products) { product in
                        NavigationLink(destination: ProductDetailView(product: product)) {
                            ProductRow(product: product)
                        }
                    }
                }
            }

            if !location.unitArray.isEmpty {
                Section(NSLocalizedString("個体", comment: "")) {
                    ForEach(location.unitArray) { unit in
                        if let product = unit.product {
                            NavigationLink(destination: ProductDetailView(product: product)) {
                                unitRow(unit)
                            }
                        } else {
                            unitRow(unit)
                        }
                    }
                }
            }

            labelsSection

            if canEdit {
                Section {
                    Button { showingAddChild = true } label: {
                        Label(NSLocalizedString("サブの場所を追加", comment: ""), systemImage: "plus")
                    }
                    Button { showingBulkMove = true } label: {
                        Label(NSLocalizedString("中身をまとめて移動", comment: ""), systemImage: "arrow.left.arrow.right")
                    }
                    .accessibilityIdentifier("bulkMoveButton")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(location.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showingEdit = true } label: {
                            Label(NSLocalizedString("場所を編集（名前・種類・親）", comment: ""), systemImage: "pencil")
                        }
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Label(NSLocalizedString("この場所を削除", comment: ""), systemImage: "trash")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let project = location.project {
                LocationFormView(project: project, editing: location)
            }
        }
        .alert(NSLocalizedString("場所を削除しますか？", comment: ""), isPresented: $confirmingDelete) {
            Button(NSLocalizedString("削除", comment: ""), role: .destructive) { deleteLocation() }
            Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) {}
        } message: {
            Text(String(format: NSLocalizedString("「%@」とそのサブの場所を削除します。中の製品・個体は削除されず「場所なし」になります。貼っていたQRラベルは空に戻り、再利用できます。", comment: ""), location.displayName))
        }
        .alert(NSLocalizedString("QRの割り当てを解除しますか？", comment: ""),
               isPresented: Binding(get: { unassigningLabel != nil },
                                    set: { if !$0 { unassigningLabel = nil } }),
               presenting: unassigningLabel) { alias in
            Button(NSLocalizedString("解除する", comment: "")) { unassign(alias); unassigningLabel = nil }
            Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) { unassigningLabel = nil }
        } message: { alias in
            Text(String(format: NSLocalizedString("%@ は空のQRに戻り、スキャンして別の品物・場所に割り当て直せます。", comment: ""), alias.code))
        }
        .alert(NSLocalizedString("QRを無効化しますか？", comment: ""),
               isPresented: Binding(get: { retiringLabel != nil },
                                    set: { if !$0 { retiringLabel = nil } }),
               presenting: retiringLabel) { alias in
            Button(NSLocalizedString("無効化する", comment: ""), role: .destructive) { retire(alias); retiringLabel = nil }
            Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) { retiringLabel = nil }
        } message: { alias in
            Text(String(format: NSLocalizedString("%@ は読み取っても使えなくなります（元に戻せません）。", comment: ""), alias.code))
        }
        .sheet(isPresented: $showingAddChild) {
            if let project = location.project {
                LocationFormView(project: project, defaultParent: location)
            }
        }
        .sheet(isPresented: $showingBulkMove) {
            if let project = location.project {
                LocationPickerSheet(project: project, excluding: location) { destination in
                    bulkMove(to: destination)
                }
            }
        }
        .alert(item: Binding(get: { moveResult.map { PresentableError(message: $0) } },
                             set: { _ in moveResult = nil })) { presentable in
            Alert(title: Text(NSLocalizedString("移動完了", comment: "")), message: Text(presentable.message),
                  dismissButton: .default(Text(NSLocalizedString("OK", comment: ""))))
        }
        .errorAlert($error)
    }

    private func unitRow(_ unit: StockUnit) -> some View {
        HStack {
            Text(unit.displayTitle)
            Spacer()
            Text(unit.status.localizedTitle).font(.caption).foregroundColor(.secondary)
        }
    }

    /// This location's QR labels: view/print, release back to blank, retire,
    /// or mint a fresh one — previously invisible and irrevocable from here.
    @ViewBuilder private var labelsSection: some View {
        Section {
            ForEach(location.activeLabels) { alias in
                NavigationLink(destination: QRLabelStudioView(code: alias.code,
                                                              projectName: location.project?.displayName ?? "",
                                                              targetName: location.displayName)) {
                    Label(alias.code, systemImage: "qrcode")
                        .font(.system(.callout, design: .monospaced))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if canEdit {
                        Button(role: .destructive) { retiringLabel = alias } label: {
                            Label(NSLocalizedString("無効化", comment: ""), systemImage: "nosign")
                        }
                        Button { unassigningLabel = alias } label: {
                            Label(NSLocalizedString("割り当て解除", comment: ""), systemImage: "minus.circle")
                        }
                        .tint(.orange)
                    }
                }
            }
            if let issuedCode {
                Label(String(format: NSLocalizedString("%@ を発行しました。上の一覧から印刷できます。", comment: ""), issuedCode),
                      systemImage: "checkmark.circle.fill")
                    .font(.footnote).foregroundColor(.green)
            }
            if canEdit {
                Button { issueLabel() } label: {
                    Label(NSLocalizedString("この場所のQRを発行", comment: ""), systemImage: "qrcode.viewfinder")
                }
            }
        } header: {
            Text(NSLocalizedString("QRラベル", comment: ""))
        } footer: {
            if !location.activeLabels.isEmpty {
                Text(NSLocalizedString("行を左にスワイプすると、割り当て解除（別の対象へ使い回す）や無効化ができます。", comment: ""))
            }
        }
    }

    private func issueLabel() {
        guard let project = location.project else { return }
        let locationID = location.objectID
        let projectID = project.objectID
        var code: String?
        let result = container.performWrite { ctx in
            guard let loc = try ctx.existingObject(with: locationID) as? Location,
                  let proj = try ctx.existingObject(with: projectID) as? Project else { return }
            let alias = try container.aliases.createAlias(for: .location(loc), in: proj, context: ctx)
            code = alias.code
        }
        switch result {
        case .success: Haptics.success(); issuedCode = code
        case .failure(let err): error = PresentableError(err)
        }
    }

    private func unassign(_ alias: CodeAlias) {
        let aliasID = alias.objectID
        let result = container.performWrite { ctx in
            guard let a = try ctx.existingObject(with: aliasID) as? CodeAlias else { return }
            container.aliases.unassign(alias: a)
        }
        if case .failure(let err) = result { error = PresentableError(err) } else { Haptics.success() }
    }

    private func retire(_ alias: CodeAlias) {
        let aliasID = alias.objectID
        let result = container.performWrite { ctx in
            guard let a = try ctx.existingObject(with: aliasID) as? CodeAlias else { return }
            container.aliases.retire(alias: a)
        }
        if case .failure(let err) = result { error = PresentableError(err) } else { Haptics.success() }
    }

    private func deleteLocation() {
        let locationID = location.objectID
        let result = container.performWrite { ctx in
            guard let loc = try ctx.existingObject(with: locationID) as? Location else { return }
            container.locations.deleteLocation(loc, in: ctx)
        }
        switch result {
        case .success: Haptics.success(); dismiss()
        case .failure(let err): error = PresentableError(err)
        }
    }

    private func bulkMove(to destination: Location) {
        let sourceID = location.objectID
        let destID = destination.objectID
        let actor = settings.effectiveOperatorName
        let result = container.performWrite { ctx in
            guard let src = try ctx.existingObject(with: sourceID) as? Location,
                  let dst = try ctx.existingObject(with: destID) as? Location else { return }
            let moved = try container.locations.bulkMoveContents(of: src, to: dst, actor: actor, in: ctx)
            DispatchQueue.main.async {
                moveResult = String(format: NSLocalizedString("製品 %d 件、個体 %d 件を移動しました。", comment: ""),
                                    moved.products, moved.units)
            }
        }
        if case .failure(let err) = result { error = PresentableError(err) }
    }
}

/// Picks a destination location within a project.
struct LocationPickerSheet: View {
    @EnvironmentObject private var container: ServiceContainer
    @Environment(\.dismiss) private var dismiss
    let project: Project
    var excluding: Location?
    var onSelect: (Location) -> Void

    var body: some View {
        NavigationView {
            List {
                ForEach(candidates) { location in
                    Button {
                        onSelect(location); dismiss()
                    } label: {
                        HStack {
                            Label(location.breadcrumb, systemImage: location.kind.systemImageName)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("移動先を選択", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(NSLocalizedString("閉じる", comment: "")) { dismiss() } } }
        }
    }

    private var candidates: [Location] {
        project.locationArray.filter { $0.objectID != excluding?.objectID }
    }
}
