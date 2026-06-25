import SwiftUI

/// Location detail with its contents and the container bulk-move action
/// (spec §4.3): move everything in this location to another location.
struct LocationDetailView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var location: Location
    let canEdit: Bool

    @State private var showingBulkMove = false
    @State private var showingAddChild = false
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
                        HStack {
                            Text(unit.displaySerial)
                            Spacer()
                            Text(unit.status.localizedTitle).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }

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
