import CoreData
import SwiftUI
import UIKit

/// Create / edit a product (spec §5.3, §12.4).
struct ProductFormView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let project: Project
    var editing: Product?

    @State private var name = ""
    @State private var sku = ""
    @State private var unitName = "pcs"
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

    private var isEditing: Bool { editing != nil }

    var body: some View {
        NavigationView {
            Form {
                Section(NSLocalizedString("基本情報", comment: "")) {
                    TextField(NSLocalizedString("製品名", comment: ""), text: $name)
                        .accessibilityIdentifier("productNameField")
                    TextField(NSLocalizedString("SKU（任意）", comment: ""), text: $sku)
                        .autocorrectionDisabled()
                        .onChange(of: sku) { _ in checkSKU() }
                    if skuWarning {
                        Label(NSLocalizedString("同じSKUの製品が既にあります", comment: ""), systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundColor(.orange)
                    }
                    TextField(NSLocalizedString("単位（例: 個, 本）", comment: ""), text: $unitName)
                }

                Section(NSLocalizedString("管理方法", comment: "")) {
                    Picker(NSLocalizedString("追跡モード", comment: ""), selection: $trackingMode) {
                        ForEach(TrackingMode.allCases) { Text($0.localizedTitle).tag($0) }
                    }
                    .disabled(isEditing) // changing mode after events would be ambiguous
                    HStack {
                        Text(NSLocalizedString("最低在庫", comment: ""))
                        Spacer()
                        TextField("0", text: $minimumStock)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                    }
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
                }

                Section(NSLocalizedString("配置", comment: "")) {
                    Picker(NSLocalizedString("フォルダ", comment: ""), selection: $folderID) {
                        Text(NSLocalizedString("なし", comment: "")).tag(NSManagedObjectID?.none)
                        ForEach(project.folderArray) { Text($0.displayName).tag(Optional($0.objectID)) }
                    }
                    Picker(NSLocalizedString("既定の場所", comment: ""), selection: $locationID) {
                        Text(NSLocalizedString("なし", comment: "")).tag(NSManagedObjectID?.none)
                        ForEach(project.locationArray) { Text($0.breadcrumb).tag(Optional($0.objectID)) }
                    }
                }

                Section(NSLocalizedString("写真", comment: "")) {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 160)
                    }
                    Button {
                        showingPhotoPicker = true
                    } label: {
                        Label(photo == nil ? NSLocalizedString("写真を追加", comment: "") : NSLocalizedString("写真を変更", comment: ""),
                              systemImage: "camera")
                    }
                }

                Section(NSLocalizedString("メモ", comment: "")) {
                    MultilineTextField(text: $note, placeholder: NSLocalizedString("メモ（任意）", comment: ""))
                        .frame(minHeight: 60)
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
        if let data = editing.photoData { photo = UIImage(data: data) }
    }

    private func checkSKU() {
        let trimmed = sku.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { skuWarning = false; return }
        skuWarning = project.productArray.contains {
            $0.objectID != editing?.objectID && ($0.sku ?? "").caseInsensitiveCompare(trimmed) == .orderedSame
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
        let photoData = photo.flatMap { ImageResizer.jpegData(from: $0) }

        let result = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: projectID) as? Project else { return }
            let folderObj = folder.flatMap { try? ctx.existingObject(with: $0) as? Folder }
            let locationObj = location.flatMap { try? ctx.existingObject(with: $0) as? Location }

            let product: Product
            if let editingID, let existing = try? ctx.existingObject(with: editingID) as? Product {
                product = existing
            } else {
                product = Product.make(in: ctx, name: values.name, project: p, sku: values.sku,
                                       unitName: values.unit.isEmpty ? "pcs" : values.unit, trackingMode: values.mode)
                container.router.assignChild(product, toSameStoreAs: p, in: ctx)
            }
            product.name = values.name
            product.sku = values.sku
            product.unitName = values.unit.isEmpty ? "pcs" : values.unit
            product.minimumStock = values.minimum
            product.note = values.note
            product.folder = folderObj
            product.defaultLocation = locationObj
            if let photoData { product.photoData = photoData }
            product.touch()

            if editingID == nil && values.mode == .quantity && values.initial > 0 {
                container.inventory.setInitialStock(product: product, quantity: values.initial,
                                                    location: locationObj, actor: actor, in: ctx)
            } else {
                container.inventory.recompute(product: product)
            }
        }
        switch result {
        case .success: dismiss()
        case .failure(let err): error = PresentableError(err)
        }
    }
}
