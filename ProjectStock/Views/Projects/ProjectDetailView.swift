import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
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
    @State private var confirmingDemoDelete = false
    @State private var error: PresentableError?
    @AppStorage("hideFirstRunGuide") private var hideFirstRunGuide = false

    private var canEdit: Bool { permission.canEdit }

    var body: some View {
        VStack(spacing: 0) {
            header
            if project.isSample { demoBanner }
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
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Dedicated, always-visible entry so sharing with others is easy
                // to find (the 共有 tab alone is easy to miss on a narrow screen).
                Button {
                    withAnimation { segment = .share }
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                }
                .accessibilityLabel(Text(NSLocalizedString("共有・招待", comment: "")))
                .accessibilityIdentifier("shareToolbarButton")

                Menu {
                    Button {
                        withAnimation { segment = .share }
                    } label: {
                        Label(NSLocalizedString("共有・メンバーを招待", comment: ""), systemImage: "person.2.badge.plus")
                    }
                    if canEdit {
                        Button { showingEdit = true } label: { Label(NSLocalizedString("編集", comment: ""), systemImage: "pencil") }
                        Button { showingPrePrint = true } label: { Label(NSLocalizedString("サンプル用QRをまとめて発行", comment: ""), systemImage: "printer") }
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
        .alert(NSLocalizedString("お試しデータを削除しますか？", comment: ""), isPresented: $confirmingDemoDelete) {
            Button(NSLocalizedString("削除", comment: ""), role: .destructive) { deleteDemoProject() }
            Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("お試し用プロジェクトと、その中の製品・QRラベル・履歴がすべて削除されます。自分で作成したプロジェクトには影響しません。", comment: ""))
        }
        .errorAlert($error)
    }

    // MARK: - Demo data banner

    /// Shown only on the seeded demo (お試し) project so users always know this
    /// data is disposable — and can dispose of it right here when they start
    /// operating for real.
    private var demoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundColor(Brand.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(NSLocalizedString("これはお試しデータです", comment: ""))
                    .font(.caption.weight(.semibold))
                Text(NSLocalizedString("使い方の確認用。実運用を始めるときは削除できます。", comment: ""))
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Button(NSLocalizedString("削除", comment: "")) { confirmingDemoDelete = true }
                .font(.caption.weight(.semibold))
                .foregroundColor(.red)
                .accessibilityIdentifier("deleteDemoProjectButton")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Brand.primary.opacity(0.08)))
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    /// Pop first, delete after the pop animation: deleting the object out from
    /// under this pushed view would fault `@ObservedObject project` mid-render.
    private func deleteDemoProject() {
        let id = project.objectID
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            _ = container.performWrite { ctx in
                guard let p = try ctx.existingObject(with: id) as? Project else { return }
                ctx.delete(p)
            }
            // Starting real operation now — bring the getting-started guide back.
            hideFirstRunGuide = false
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Circle().fill(project.color.color).frame(width: 12, height: 12)
                Button {
                    withAnimation { segment = .share }
                } label: {
                    SharePermissionBadge(permission: permission)
                }
                .buttonStyle(.plain)
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

                    Button { showingPrePrint = true } label: {
                        Label(NSLocalizedString("サンプル用QRをまとめて発行", comment: ""), systemImage: "printer")
                    }
                    .accessibilityIdentifier("prePrintButton")
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
