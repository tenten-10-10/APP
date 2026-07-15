import SwiftUI
import CoreData

/// 未登録バーコードのその場登録（ハンディの「7秒で戦力化」動線）。商品名を
/// 入れて保存するだけでバーコード→製品のひも付けが完成し、入庫モード中なら
/// そのまま1回分を計上してカメラに戻る。バーコードは `CodeAlias.publicCode` に
/// 数字のまま保存（アプリQRの "IQ…" 形式と衝突しない）し、`Product.sku` にも
/// 控えとして書く — どちらも既存属性でスキーマ変更なし。
struct HandyRegisterSheet: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let code: String
    let mode: HandyMode
    let amount: Int
    @ObservedObject var session: HandySession
    let onCard: (HandyCard) -> Void

    // 前回の登録先を覚えて既定にする（棚作業は同じプロジェクトが続く）。
    @AppStorage("handy.lastProjectURI") private var lastProjectURI = ""

    @FetchRequest(fetchRequest: {
        let r = Project.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Project.updatedAt, ascending: false)]
        r.predicate = NSPredicate(format: "archivedAt == nil")
        return r
    }(), animation: .default) private var projects: FetchedResults<Project>

    @State private var name = ""
    @State private var projectID: NSManagedObjectID?
    @State private var folderID: NSManagedObjectID?
    @State private var locationID: NSManagedObjectID?
    @State private var error: PresentableError?
    @FocusState private var nameFocused: Bool

    /// 書き込めるプロジェクトのみ（お試しデータは除外）。
    private var editableProjects: [Project] {
        projects.filter { !$0.isSample && container.sharing.canEdit($0) }
    }

    private var selectedProject: Project? {
        guard let projectID else { return nil }
        return editableProjects.first { $0.objectID == projectID }
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Label("\(BarcodeCode.typeName(for: code))  \(code)", systemImage: "barcode")
                        .font(.callout.monospacedDigit())
                } footer: {
                    Text(NSLocalizedString("このバーコードを商品にひも付けます。次からはスキャンするだけで照会・入庫・出庫できます。", comment: ""))
                }
                Section(NSLocalizedString("商品", comment: "")) {
                    TextField(NSLocalizedString("商品名", comment: ""), text: $name)
                        .focused($nameFocused)
                        .accessibilityIdentifier("handyRegisterNameField")
                }
                Section(NSLocalizedString("登録先", comment: "")) {
                    projectPicker
                    if let project = selectedProject {
                        folderPicker(project)
                        locationPicker(project)
                    }
                }
                Section {
                    Button(saveButtonTitle) { save() }
                        .font(.body.weight(.semibold))
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedProject == nil)
                        .accessibilityIdentifier("handyRegisterSave")
                }
            }
            .navigationTitle(NSLocalizedString("バーコードを登録", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("キャンセル", comment: "")) { dismiss() }
                }
            }
            .errorAlert($error)
            .onAppear(perform: prepareDefaults)
        }
    }

    private var saveButtonTitle: String {
        mode == .receive
            ? String(format: NSLocalizedString("登録して %d 入庫する", comment: ""), amount)
            : NSLocalizedString("登録してつづける", comment: "")
    }

    private var projectPicker: some View {
        Picker(NSLocalizedString("プロジェクト", comment: ""), selection: $projectID) {
            ForEach(editableProjects) { project in
                Text(project.displayName).tag(Optional(project.objectID))
            }
        }
    }

    private func folderPicker(_ project: Project) -> some View {
        Picker(NSLocalizedString("フォルダ", comment: ""), selection: $folderID) {
            Text(NSLocalizedString("なし", comment: "")).tag(NSManagedObjectID?.none)
            ForEach(project.folderArray) { folder in
                Text(folder.displayName).tag(Optional(folder.objectID))
            }
        }
    }

    private func locationPicker(_ project: Project) -> some View {
        Picker(NSLocalizedString("保管場所", comment: ""), selection: $locationID) {
            Text(NSLocalizedString("なし", comment: "")).tag(NSManagedObjectID?.none)
            ForEach(project.locationArray) { location in
                Text(location.breadcrumb).tag(Optional(location.objectID))
            }
        }
    }

    private func prepareDefaults() {
        if projectID == nil {
            if let url = URL(string: lastProjectURI),
               let oid = container.viewContext.persistentStoreCoordinator?
                   .managedObjectID(forURIRepresentation: url),
               editableProjects.contains(where: { $0.objectID == oid }) {
                projectID = oid
            } else {
                projectID = editableProjects.first?.objectID
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { nameFocused = true }
    }

    private func save() {
        guard let project = selectedProject else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let digits = code
        let projectOID = project.objectID
        let folderOID = folderID
        let locationOID = locationID
        let actor = settings.effectiveOperatorName
        let applyReceive = (mode == .receive)
        let qty = Double(amount)
        var eventID: NSManagedObjectID?

        let result = container.performWrite { ctx in
            guard let proj = try ctx.existingObject(with: projectOID) as? Project else { return }
            // 同じバーコードの二重登録はここで止める（グローバル一意）。
            if container.aliases.codeExists(digits, in: ctx) {
                throw AppError.underlying(NSLocalizedString("このバーコードは既に登録されています。", comment: ""))
            }
            let folder = try folderOID.map { try ctx.existingObject(with: $0) as? Folder } ?? nil
            let location = try locationOID.map { try ctx.existingObject(with: $0) as? Location } ?? nil
            let product = Product.make(in: ctx, name: trimmed, project: proj, sku: digits,
                                       unitName: NSLocalizedString("個", comment: ""),
                                       trackingMode: .quantity, folder: folder)
            product.defaultLocation = location
            container.router.assignChild(product, toSameStoreAs: proj, in: ctx)
            let alias = CodeAlias.make(in: ctx, publicCode: digits, project: proj)
            container.router.assignChild(alias, toSameStoreAs: proj, in: ctx)
            try container.aliases.assign(alias: alias, to: .product(product))
            if applyReceive {
                let event = container.inventory.receive(product: product, quantity: qty,
                                                        location: location, actor: actor,
                                                        note: NSLocalizedString("ハンディ", comment: ""), in: ctx)
                try ctx.obtainPermanentIDs(for: [event])
                eventID = event.objectID
            }
        }
        switch result {
        case .success:
            lastProjectURI = projectOID.uriRepresentation().absoluteString
            Haptics.success()
            if applyReceive {
                let detail = "+\(qty.quantityString) " + HandyMode.receive.title
                session.add(HandyEntry(eventID: eventID, title: trimmed, detail: detail))
                onCard(HandyCard(kind: .success, title: trimmed,
                                 subtitle: String(format: NSLocalizedString("登録して %@ を記録しました", comment: ""), detail)))
            } else {
                onCard(HandyCard(kind: .success, title: trimmed,
                                 subtitle: NSLocalizedString("登録しました。次からはスキャンだけでOKです。", comment: "")))
            }
            dismiss()
        case .failure(let err):
            error = PresentableError(err)
        }
    }
}
