import CoreData
import SwiftUI
import UIKit

/// Create / edit a product (spec §5.3, §12.4).
struct ProductFormView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var project: Project
    var editing: Product?

    @State private var name = ""
    @State private var sku = ""
    @State private var unitName = NSLocalizedString("個", comment: "default unit")
    @State private var trackingMode: TrackingMode = .quantity
    @State private var minimumStock = ""
    @State private var initialQuantity = ""
    @State private var note = ""
    @State private var folderID: NSManagedObjectID?
    @State private var locationID: NSManagedObjectID?
    @State private var photo: UIImage?
    @State private var showingPhotoPicker = false
    @State private var error: PresentableError?
    @State private var skuWarning = false
    @State private var showDetails = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var showNewLocation = false
    @State private var newLocationName = ""

    private var isEditing: Bool { editing != nil }

    var body: some View {
        NavigationView {
            Form {
                Section(NSLocalizedString("基本情報", comment: "")) {
                    TextField(NSLocalizedString("製品名", comment: ""), text: $name)
                        .accessibilityIdentifier("productNameField")
                }

                Section(NSLocalizedString("管理方法", comment: "")) {
                    Picker(NSLocalizedString("追跡モード", comment: ""), selection: $trackingMode) {
                        ForEach(TrackingMode.allCases) { Text($0.localizedTitle).tag($0) }
                    }
                    .disabled(isEditing) // changing mode after events would be ambiguous
                    if !isEditing && trackingMode == .quantity {
                        HStack {
                            Text(NSLocalizedString("初期在庫", comment: ""))
                            Spacer()
                            TextField("0", text: $initialQuantity)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .frame(maxWidth: 100)
                                .accessibilityIdentifier("initialQuantityField")
                        }
                    }
                    // 単位と最低在庫は折りたたみの外に常時表示する。詳細設定の
                    // 中に隠れていると大半のユーザーが最低在庫0のまま保存し、
                    // 「要補充」表示が一度も機能しないアプリになる。
                    TextField(NSLocalizedString("単位（例: 個, 本）", comment: ""), text: $unitName)
                    if trackingMode == .quantity {
                        HStack {
                            Text(NSLocalizedString("最低在庫", comment: ""))
                            Spacer()
                            TextField("0", text: $minimumStock)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .frame(maxWidth: 100)
                        }
                    }
                } footer: {
                    if trackingMode == .quantity {
                        Text(NSLocalizedString("最低在庫を設定すると、在庫がそれを下回ったときに「要補充」と表示されます。", comment: ""))
                    }
                }

                Section {
                    Picker(NSLocalizedString("フォルダ", comment: ""), selection: $folderID) {
                        Text(NSLocalizedString("なし", comment: "")).tag(NSManagedObjectID?.none)
                        ForEach(project.folderArray) { Text($0.displayName).tag(Optional($0.objectID)) }
                    }
                    Button { showNewFolder = true } label: {
                        Label(NSLocalizedString("新しいフォルダを作成", comment: ""), systemImage: "folder.badge.plus")
                    }
                    Picker(NSLocalizedString("既定の場所", comment: ""), selection: $locationID) {
                        Text(NSLocalizedString("なし", comment: "")).tag(NSManagedObjectID?.none)
                        ForEach(project.locationArray) { Text($0.breadcrumb).tag(Optional($0.objectID)) }
                    }
                    Button { showNewLocation = true } label: {
                        Label(NSLocalizedString("新しい場所を作成", comment: ""), systemImage: "mappin.circle")
                    }
                } header: {
                    Text(NSLocalizedString("配置", comment: ""))
                } footer: {
                    Text(NSLocalizedString("ここから新しいフォルダや場所を作って、すぐに選べます。", comment: ""))
                }

                Section {
                    DisclosureGroup(isExpanded: $showDetails) {
                        TextField(NSLocalizedString("社内コード（任意）", comment: ""), text: $sku)
                            .autocorrectionDisabled()
                            .onChange(of: sku) { _ in checkSKU() }
                        if skuWarning {
                            Label(NSLocalizedString("同じ社内コードの製品が既にあります", comment: ""), systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundColor(.orange)
                        }
                        if let photo {
                            Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 160)
                        }
                        Button {
                            showingPhotoPicker = true
                        } label: {
                            Label(photo == nil ? NSLocalizedString("写真を追加", comment: "") : NSLocalizedString("写真を変更", comment: ""),
                                  systemImage: "camera")
                        }
                        MultilineTextField(text: $note, placeholder: NSLocalizedString("メモ（任意）", comment: ""))
                            .frame(minHeight: 60)
                    } label: {
                        Text(NSLocalizedString("詳細設定（任意）", comment: ""))
                    }
                }
            }
            .navigationTitle(isEditing ? NSLocalizedString("製品を編集", comment: "") : NSLocalizedString("新規製品", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(NSLocalizedString("キャンセル", comment: "")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("保存", comment: "")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("saveProductButton")
                }
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PhotoPicker { picked in photo = picked }
            }
            .alert(NSLocalizedString("新しいフォルダ", comment: ""), isPresented: $showNewFolder) {
                TextField(NSLocalizedString("フォルダ名", comment: ""), text: $newFolderName)
                Button(NSLocalizedString("作成", comment: "")) { createFolderInline() }
                Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) { newFolderName = "" }
            }
            .alert(NSLocalizedString("新しい場所", comment: ""), isPresented: $showNewLocation) {
                TextField(NSLocalizedString("場所の名前", comment: ""), text: $newLocationName)
                Button(NSLocalizedString("作成", comment: "")) { createLocationInline() }
                Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) { newLocationName = "" }
            }
            .onAppear(perform: load)
            .errorAlert($error)
        }
    }

    private func load() {
        guard let editing else {
            // New product: start in the project's preferred tracking mode.
            trackingMode = project.defaultTrackingMode
            return
        }
        name = editing.displayName
        sku = editing.sku ?? ""
        unitName = editing.unitLabel
        trackingMode = editing.trackingMode
        minimumStock = editing.minimumStock == 0 ? "" : editing.minimumStock.quantityString
        note = editing.note ?? ""
        folderID = editing.folder?.objectID
        locationID = editing.defaultLocation?.objectID
        if let data = editing.photoThumbnail { photo = UIImage(data: data) }
    }

    private func checkSKU() {
        let trimmed = sku.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { skuWarning = false; return }
        skuWarning = project.productArray.contains {
            $0.objectID != editing?.objectID && ($0.sku ?? "").caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    /// Create a folder in this project from the form and select it immediately.
    private func createFolderInline() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        guard !name.isEmpty else { return }
        let projectID = project.objectID
        var newID: NSManagedObjectID?
        let result = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: projectID) as? Project else { return }
            let folder = Folder.make(in: ctx, name: name, project: p)
            container.router.assignChild(folder, toSameStoreAs: p, in: ctx)
            try ctx.obtainPermanentIDs(for: [folder])
            newID = folder.objectID
        }
        switch result {
        case .success: if let newID { folderID = newID }
        case .failure(let err): error = PresentableError(err)
        }
    }

    /// Create a location in this project from the form and select it immediately.
    private func createLocationInline() {
        let name = newLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        newLocationName = ""
        guard !name.isEmpty else { return }
        let projectID = project.objectID
        var newID: NSManagedObjectID?
        let result = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: projectID) as? Project else { return }
            let location = Location.make(in: ctx, name: name, project: p, kind: .container)
            container.router.assignChild(location, toSameStoreAs: p, in: ctx)
            try ctx.obtainPermanentIDs(for: [location])
            newID = location.objectID
        }
        switch result {
        case .success: if let newID { locationID = newID }
        case .failure(let err): error = PresentableError(err)
        }
    }

    private func save() {
        let values = (name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                      sku: sku.trimmingCharacters(in: .whitespaces),
                      unit: unitName.trimmingCharacters(in: .whitespaces),
                      mode: trackingMode,
                      minimum: Double(minimumStock) ?? 0,
                      initial: Double(initialQuantity) ?? 0,
                      note: note)
        let folder = folderID
        let location = locationID
        let projectID = project.objectID
        let editingID = editing?.objectID
        let actor = settings.effectiveOperatorName
        let photoThumbnail = photo.flatMap { ImageResizer.jpegData(from: $0, maxEdge: 250) }

        let result = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: projectID) as? Project else { return }
            let folderObj = folder.flatMap { try? ctx.existingObject(with: $0) as? Folder }
            let locationObj = location.flatMap { try? ctx.existingObject(with: $0) as? Location }

            let product: Product
            if let editingID, let existing = try? ctx.existingObject(with: editingID) as? Product {
                product = existing
            } else {
                product = Product.make(in: ctx, name: values.name, project: p, sku: values.sku,
                                       unitName: values.unit.isEmpty ? NSLocalizedString("個", comment: "") : values.unit, trackingMode: values.mode)
                container.router.assignChild(product, toSameStoreAs: p, in: ctx)
            }
            product.name = values.name
            product.sku = values.sku
            product.unitName = values.unit.isEmpty ? NSLocalizedString("個", comment: "") : values.unit
            product.minimumStock = values.minimum
            product.note = values.note
            product.folder = folderObj
            product.defaultLocation = locationObj
            if let photoThumbnail { product.photoThumbnail = photoThumbnail }
            product.touch()

            if editingID == nil && values.mode == .quantity && values.initial > 0 {
                container.inventory.setInitialStock(product: product, quantity: values.initial,
                                                    location: locationObj, actor: actor, in: ctx)
            } else {
                container.inventory.recompute(product: product)
            }
        }
        switch result {
        case .success: Haptics.success(); dismiss()
        case .failure(let err): error = PresentableError(err)
        }
    }
}
