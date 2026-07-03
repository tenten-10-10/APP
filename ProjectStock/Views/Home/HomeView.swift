import SwiftUI
import CoreData

/// Dashboard tab: totals header + three alert sections (low stock, overdue
/// loans, expiring lots). All sections filter in Swift from broad fetches
/// because isLowStock / isExpired / expiresSoon() are computed properties.
struct HomeView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var webBorrow: WebBorrowInbox

    // Broad fetches — filter in Swift (computed properties can't be predicates)
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Project.updatedAt, ascending: false)],
        predicate: NSPredicate(format: "archivedAt == nil"),
        animation: .default
    ) private var projects: FetchedResults<Project>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Product.name, ascending: true)],
        predicate: NSPredicate(format: "isArchived == NO"),
        animation: .default
    ) private var products: FetchedResults<Product>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \StockUnit.expiresAt, ascending: true)],
        predicate: NSPredicate(format: "kindRaw == %@ AND expiresAt != nil", UnitKind.lot.rawValue),
        animation: .default
    ) private var lotUnits: FetchedResults<StockUnit>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \StockUnit.updatedAt, ascending: true)],
        predicate: NSPredicate(format: "statusRaw == %@", UnitStatus.checkedOut.rawValue),
        animation: .default
    ) private var checkedOutUnits: FetchedResults<StockUnit>

    // All QR labels. We deliberately DON'T filter by `project.isSample` in the
    // fetch predicate: a relationship-traversing predicate requires a SQL JOIN
    // that CloudKit's mirrored multi-store (private + shared) coordinator can't
    // execute, and it throws an uncatchable exception on launch. Filtering in
    // Swift (object-level relationship access) is store-safe.
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CodeAlias.createdAt, ascending: false)],
        animation: .default
    ) private var labels: FetchedResults<CodeAlias>

    @State private var showSearch = false
    // Pre-print (blank QR) flow driven from the Home hero.
    @State private var prePrintProject: Project?
    @State private var showCreateProjectForPrePrint = false
    @State private var pendingPrePrintProject: Project?
    @State private var showProjectPicker = false
    @State private var goScan = false
    @AppStorage("hideFirstRunGuide") private var hideSetupGuide = false

    // MARK: - Derived

    private var lowStockProducts: [Product] {
        products.filter { $0.isLowStock }
    }

    private var overdueLoans: [Loan] {
        checkedOutUnits
            .compactMap { container.inventory.currentLoan(for: $0) }
            .filter { $0.isOverdue }
            .sorted { ($0.dueAt ?? .distantPast) < ($1.dueAt ?? .distantPast) }
    }

    private var expiringLots: [StockUnit] {
        lotUnits.filter { $0.isExpired || $0.expiresSoon() }
    }

    private var totalProductCount: Int { products.count }
    private var totalLowStockCount: Int { lowStockProducts.count }
    private var totalOverdueCount: Int { overdueLoans.count }

    private var hasAlerts: Bool {
        !lowStockProducts.isEmpty || !overdueLoans.isEmpty || !expiringLots.isEmpty
    }

    // MARK: - First-run guide

    /// The user's own projects. Demo (お試し) data is excluded everywhere the
    /// guide or the pre-print hero reasons about setup progress, so trying the
    /// demo never masks the real getting-started steps — and blank QRs minted
    /// from Home never land inside demo data that will later be deleted.
    private var realProjects: [Project] { projects.filter { !$0.isSample } }
    private var hasProject: Bool { !realProjects.isEmpty }
    // Exclude demo (お試し) labels here in Swift, not in the fetch predicate.
    private var hasBlankLabel: Bool { labels.contains { $0.project?.isSample != true } }
    private var hasProduct: Bool { products.contains { $0.project?.isSample != true } }
    // Sample-first flow: ① プロジェクト → ② 空QRを印刷して貼る → ③ スキャンして登録.
    private var setupComplete: Bool { hasProject && hasBlankLabel && hasProduct }
    private var showGuide: Bool { !hideSetupGuide && !setupComplete }

    /// Entry point for the "print blank QR labels" hero action. A project is
    /// required to mint codes, so bootstrap or disambiguate one first.
    private func startPrePrint() {
        if realProjects.isEmpty {
            showCreateProjectForPrePrint = true
        } else if realProjects.count == 1 {
            prePrintProject = realProjects.first
        } else {
            showProjectPicker = true
        }
    }

    // MARK: - Body

    var body: some View {
        List {
            startHubSection
            if webBorrow.pendingCount > 0 { webBorrowSection }
            summaryCard
            if hasAlerts {
                lowStockSection
                overdueLoansSection
                expiringLotsSection
            } else {
                allGoodSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("ホーム", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel(Text(NSLocalizedString("検索", comment: "")))
            }
        }
        .background(navigationLinks)
        .sheet(isPresented: $showSearch) {
            SearchView()
        }
        .sheet(isPresented: $showCreateProjectForPrePrint, onDismiss: {
            // Present the pre-print sheet only after the create sheet has fully
            // dismissed, avoiding a sheet-over-sheet presentation race.
            if let created = pendingPrePrintProject {
                pendingPrePrintProject = nil
                prePrintProject = created
            }
        }) {
            ProjectFormView(onCreated: { pendingPrePrintProject = $0 })
        }
        .sheet(item: $prePrintProject) { project in
            PrePrintView(project: project)
        }
        .confirmationDialog(NSLocalizedString("どのプロジェクトの空QRを印刷しますか？", comment: ""),
                            isPresented: $showProjectPicker, titleVisibility: .visible) {
            ForEach(realProjects) { project in
                Button(project.displayName) { prePrintProject = project }
            }
            Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) {}
        }
    }

    // MARK: - Start hub (hero) — print blank QR + scan to register

    /// The primary call-to-action block at the top of Home. It makes "print
    /// blank QR labels" the headline action (previously buried) and, until the
    /// first sample is registered, shows a 3-step getting-started checklist.
    private var startHubSection: some View {
        Section {
            if showGuide {
                VStack(alignment: .leading, spacing: 12) {
                    guideStep(index: 1, title: NSLocalizedString("プロジェクトを作る", comment: ""), done: hasProject)
                    guideStep(index: 2, title: NSLocalizedString("空のQRラベルを印刷して貼る", comment: ""), done: hasBlankLabel)
                    guideStep(index: 3, title: NSLocalizedString("スキャンして「これは○○」と登録", comment: ""), done: hasProduct)
                }
                .padding(.vertical, 2)
            }

            VStack(spacing: 10) {
                Button { startPrePrint() } label: {
                    heroButtonLabel(systemImage: "printer.fill",
                                    title: NSLocalizedString("空のQRラベルを印刷", comment: ""),
                                    subtitle: NSLocalizedString("A4にまとめて印刷。サンプルが届く前でもOK", comment: ""),
                                    tint: .white)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("printBlankQRButton")

                Button { goScan = true } label: {
                    heroButtonLabel(systemImage: "qrcode.viewfinder",
                                    title: NSLocalizedString("スキャンして登録", comment: ""),
                                    subtitle: NSLocalizedString("貼ったQRを読み取って「これは○○」と登録", comment: ""),
                                    tint: Brand.primary)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("registerSampleButton")
            }
            .padding(.vertical, 4)
        } header: {
            HStack {
                Label(NSLocalizedString("サンプルを登録する", comment: ""), systemImage: "sparkles")
                Spacer()
                if showGuide {
                    Button(NSLocalizedString("閉じる", comment: "")) { hideSetupGuide = true }
                        .font(.caption)
                }
            }
        } footer: {
            if showGuide {
                Text(NSLocalizedString("① 空のQRを現物や棚・箱に貼り、② スキャンして製品を登録します。届く前に空QRを刷っておくとスムーズです。", comment: ""))
            }
        }
    }

    private func guideStep(index: Int, title: String, done: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(index).circle")
                .font(.title3)
                .foregroundColor(done ? .green : Brand.primary)
            Text(title)
                .strikethrough(done)
                .foregroundColor(done ? .secondary : .primary)
            Spacer()
        }
        .font(.subheadline)
    }

    private func heroButtonLabel(systemImage: String, title: String, subtitle: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption2).opacity(0.85)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).opacity(0.6)
        }
        .foregroundColor(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Hidden link so a button tap can push the scanner.
    @ViewBuilder private var navigationLinks: some View {
        NavigationLink(isActive: $goScan) {
            ScanTabView()
        } label: { EmptyView() }
        .opacity(0)
    }

    // MARK: - Web borrow inbox entry

    private var webBorrowSection: some View {
        Section {
            NavigationLink(destination: WebBorrowInboxView()) {
                HStack(spacing: 12) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.title2)
                        .foregroundColor(Brand.primary)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Web借用リクエスト", comment: ""))
                            .font(.subheadline.weight(.semibold))
                        Text(String(format: NSLocalizedString("%d 件の承認待ち", comment: ""), webBorrow.pendingCount))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(webBorrow.pendingCount)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.red))
                        .foregroundColor(.white)
                }
                .padding(.vertical, 2)
            }
            .accessibilityIdentifier("webBorrowInboxButton")
        }
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        Section {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Brand.gradient)
                    .shadow(color: Brand.gradientEnd.opacity(0.3),
                            radius: 10, y: 4)

                HStack(spacing: 0) {
                    metricCell(
                        value: "\(projects.count)",
                        label: NSLocalizedString("プロジェクト", comment: "")
                    )
                    divider
                    metricCell(
                        value: "\(totalProductCount)",
                        label: NSLocalizedString("製品", comment: "")
                    )
                    divider
                    metricCell(
                        value: "\(totalLowStockCount)",
                        label: NSLocalizedString("低在庫", comment: "")
                    )
                    divider
                    metricCell(
                        value: "\(totalOverdueCount)",
                        label: NSLocalizedString("期限超過", comment: "")
                    )
                }
                .padding(.vertical, 18)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private func metricCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundColor(.white)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label) + Text(": ") + Text(value))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.25))
            .frame(width: 1, height: 36)
    }

    // MARK: - Low stock

    @ViewBuilder
    private var lowStockSection: some View {
        if !lowStockProducts.isEmpty {
            Section {
                ForEach(lowStockProducts) { product in
                    NavigationLink(destination: ProductDetailView(product: product)) {
                        LowStockRow(product: product)
                    }
                }
            } header: {
                Label(NSLocalizedString("低在庫", comment: ""), systemImage: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Overdue loans

    @ViewBuilder
    private var overdueLoansSection: some View {
        if !overdueLoans.isEmpty {
            Section {
                ForEach(overdueLoans) { loan in
                    NavigationLink(destination: LoansView()) {
                        OverdueLoanRow(loan: loan)
                    }
                }
            } header: {
                Label(NSLocalizedString("貸出の期限超過", comment: ""), systemImage: "clock.badge.exclamationmark.fill")
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Expiring lots

    @ViewBuilder
    private var expiringLotsSection: some View {
        if !expiringLots.isEmpty {
            Section {
                ForEach(expiringLots) { lot in
                    NavigationLink(destination: LotDetailView(lot: lot)) {
                        ExpiringLotRow(lot: lot)
                    }
                }
            } header: {
                Label(NSLocalizedString("期限が近いロット", comment: ""), systemImage: "calendar.badge.exclamationmark")
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - All-good empty state

    private var allGoodSection: some View {
        Section {
            EmptyStateView(
                systemImage: "checkmark.seal.fill",
                title: NSLocalizedString("問題なし", comment: ""),
                message: NSLocalizedString("低在庫・期限超過・期限間近のロットはありません。", comment: "")
            )
            .listRowBackground(Color.clear)
        }
    }
}

// MARK: - Row subviews

private struct LowStockRow: View {
    @ObservedObject var product: Product

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .foregroundColor(.orange)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(product.displayName)
                    .font(.subheadline).bold()
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(String(format: NSLocalizedString("残: %@", comment: ""),
                                product.currentQuantity.quantityString))
                        .font(.caption).foregroundColor(.orange)
                    Text("/")
                        .font(.caption).foregroundColor(.secondary)
                    Text(String(format: NSLocalizedString("最低: %@", comment: ""),
                                product.minimumStock.quantityString))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            LowStockChip()
        }
        .padding(.vertical, 2)
    }
}

private struct OverdueLoanRow: View {
    let loan: Loan

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(loan.unit.displayTitle)
                    .font(.subheadline).bold()
                    .lineLimit(1)
                Spacer()
                OverdueChip()
            }
            if let product = loan.unit.product {
                Text(product.displayName)
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle").font(.caption2)
                Text(loan.borrowerDisplay)
            }
            .font(.caption).foregroundColor(.secondary)
            if let due = loan.dueAt {
                Text(String(format: NSLocalizedString("期限: %@", comment: ""),
                            DateFormatters.dateTime.string(from: due)))
                    .font(.caption2).foregroundColor(.red)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ExpiringLotRow: View {
    @ObservedObject var lot: StockUnit

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .foregroundColor(lot.isExpired ? .red : .orange)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(lot.lotNumberDisplay)
                    .font(.subheadline).bold()
                    .lineLimit(1)
                if let product = lot.product {
                    Text(product.displayName)
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                if let expiry = lot.expiresAt {
                    Text(DateFormatters.day.string(from: expiry))
                        .font(.caption2)
                        .foregroundColor(lot.isExpired ? .red : .secondary)
                }
            }
            Spacer()
            ExpiryChip(unit: lot)
        }
        .padding(.vertical, 2)
    }
}
