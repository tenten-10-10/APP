import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var project: Project

    enum Segment: String, CaseIterable, Identifiable {
        case products, folders, locations, activity, share
        var id: String { rawValue }
        var title: String {
            switch self {
            case .products:  return NSLocalizedString("製品", comment: "")
            case .folders:   return NSLocalizedString("フォルダ", comment: "")
            case .locations: return NSLocalizedString("場所", comment: "")
            case .activity:  return NSLocalizedString("活動", comment: "")
            case .share:     return NSLocalizedString("共有", comment: "")
            }
        }
    }

    @State private var segment: Segment = .products
    @State private var permission: SharePermission = .notShared
    @State private var showingAddProduct = false
    @State private var showingAddLocation = false
    @State private var showingAddFolder = false
    @State private var newFolderName = ""
    @State private var showingEdit = false
    @State private var showingPrePrint = false
    @State private var error: PresentableError?

    private var canEdit: Bool { permission.canEdit }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            List {
                switch segment {
                case .products:  productsSection
                case .folders:   foldersSection
                case .locations: locationsSection
                case .activity:  EventListView(events: project.eventArray, onCorrect: canEdit ? correct : nil)
                case .share:     ProjectShareSection(project: project, permission: $permission)
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle(project.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if canEdit {
                        Button { showingEdit = true } label: { Label(NSLocalizedString("編集", comment: ""), systemImage: "pencil") }
                        Button { showingPrePrint = true } label: { Label(NSLocalizedString("QRラベルを先に印刷", comment: ""), systemImage: "printer") }
                        if project.isArchived {
                            Button { setArchived(false) } label: { Label(NSLocalizedString("アーカイブ解除", comment: ""), systemImage: "tray.and.arrow.up") }
                        } else {
                            Button { setArchived(true) } label: { Label(NSLocalizedString("アーカイブ", comment: ""), systemImage: "archivebox") }
                        }
                    } else {
                        Label(NSLocalizedString("読み取り専用", comment: ""), systemImage: "eye")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear { permission = container.sharing.permission(for: project) }
        .sheet(isPresented: $showingAddProduct) { ProductFormView(project: project) }
        .sheet(isPresented: $showingAddLocation) { LocationFormView(project: project) }
        .sheet(isPresented: $showingEdit) { ProjectFormView(project: project) }
        .sheet(isPresented: $showingPrePrint) { PrePrintView(project: project) }
        .alert(NSLocalizedString("新規フォルダ", comment: ""), isPresented: $showingAddFolder) {
            TextField(NSLocalizedString("フォルダ名", comment: ""), text: $newFolderName)
            Button(NSLocalizedString("作成", comment: "")) { addFolder() }
            Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) { newFolderName = "" }
        }
        .errorAlert($error)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Circle().fill(project.color.color).frame(width: 12, height: 12)
                SharePermissionBadge(permission: permission)
                if project.isArchived {
                    Label(NSLocalizedString("アーカイブ済み", comment: ""), systemImage: "archivebox")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 16) {
                MetricView(title: NSLocalizedString("製品数", comment: ""), value: "\(project.activeProductCount)")
                MetricView(title: NSLocalizedString("要補充", comment: ""), value: "\(project.lowStockCount)")
                MetricView(title: NSLocalizedString("ラベル", comment: ""), value: "\(project.labelArray.count)")
                Spacer()
            }
        }
        .padding(.horizontal).padding(.top, 8)
    }

    // MARK: - Sections

    @ViewBuilder private var productsSection: some View {
        let products = project.productArray.filter { !$0.isArchived }
        if products.isEmpty {
            VStack(spacing: 14) {
                EmptyStateView(systemImage: project.defaultTrackingMode.systemImageName,
                               title: NSLocalizedString("最初の製品を追加しましょう", comment: ""),
                               message: project.defaultTrackingMode.explanation)
                if canEdit {
                    Button { showingAddProduct = true } label: {
                        Label(NSLocalizedString("製品を追加", comment: ""), systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("addProductButton")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
        } else {
            if canEdit {
                Button { showingAddProduct = true } label: {
                    Label(NSLocalizedString("製品を追加", comment: ""), systemImage: "plus")
                }
                .accessibilityIdentifier("addProductButton")
            }
            ForEach(products) { product in
                NavigationLink(destination: ProductDetailView(product: product)) {
                    ProductRow(product: product)
                }
            }
        }
    }

    @ViewBuilder private var foldersSection: some View {
        if canEdit {
            Button { showingAddFolder = true } label: {
                Label(NSLocalizedString("フォルダを追加", comment: ""), systemImage: "folder.badge.plus")
            }
        }
        let folders = project.folderArray
        if folders.isEmpty {
            EmptyStateView(systemImage: "folder", title: NSLocalizedString("フォルダがありません", comment: ""))
        } else {
            ForEach(folders) { folder in
                HStack {
                    Label(folder.displayName, systemImage: "folder")
                    Spacer()
                    Text("\(folder.productArray.count)").foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var locationsSection: some View {
        if canEdit {
            Button { showingAddLocation = true } label: {
                Label(NSLocalizedString("場所を追加", comment: ""), systemImage: "plus")
            }
        }
        let roots = project.locationArray.filter { $0.parent == nil }
        if roots.isEmpty {
            EmptyStateView(systemImage: "tray.2", title: NSLocalizedString("場所がありません", comment: ""))
        } else {
            ForEach(roots) { location in
                NavigationLink(destination: LocationDetailView(location: location, canEdit: canEdit)) {
                    LocationRow(location: location)
                }
            }
        }
    }

    // MARK: - Actions

    private func addFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        guard !name.isEmpty else { return }
        let projectID = project.objectID
        let result = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: projectID) as? Project else { return }
            let folder = Folder.make(in: ctx, name: name, project: p)
            container.router.assignChild(folder, toSameStoreAs: p, in: ctx)
        }
        if case .failure(let err) = result { error = PresentableError(err) }
    }

    private func setArchived(_ archived: Bool) {
        let projectID = project.objectID
        _ = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: projectID) as? Project else { return }
            if archived { container.projects.archive(p) } else { container.projects.unarchive(p) }
        }
    }

    private func correct(_ event: InventoryEvent) {
        let eventID = event.objectID
        let actor = settings.effectiveOperatorName
        let result = container.performWrite { ctx in
            guard let original = try ctx.existingObject(with: eventID) as? InventoryEvent else { return }
            container.inventory.reverse(event: original, actor: actor,
                                        note: NSLocalizedString("UIからの訂正", comment: ""), in: ctx)
        }
        if case .failure(let err) = result { error = PresentableError(err) }
    }
}

struct ProductRow: View {
    @ObservedObject var product: Product
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(product.displayName).font(.body).lineLimit(1)
                HStack(spacing: 6) {
                    if let sku = product.sku, !sku.isEmpty {
                        Text(sku).font(.caption2).foregroundColor(.secondary)
                    }
                    Text(product.trackingMode.localizedTitle).font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(product.currentQuantity.quantityString) \(product.unitLabel)")
                    .font(.callout).monospacedDigit()
                if product.isLowStock { LowStockChip() }
            }
        }
        .padding(.vertical, 2)
    }
}

struct LocationRow: View {
    @ObservedObject var location: Location
    var body: some View {
        HStack {
            Label(location.displayName, systemImage: location.kind.systemImageName)
            Spacer()
            let count = location.productArray.count + location.unitArray.count + location.childArray.count
            if count > 0 { Text("\(count)").foregroundColor(.secondary) }
        }
    }
}
