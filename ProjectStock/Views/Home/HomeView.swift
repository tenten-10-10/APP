import SwiftUI
import CoreData

/// Dashboard tab: totals header + three alert sections (low stock, overdue
/// loans, expiring lots). All sections filter in Swift from broad fetches
/// because isLowStock / isExpired / expiresSoon() are computed properties.
struct HomeView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings

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

    @State private var showSearch = false

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

    // MARK: - Body

    var body: some View {
        List {
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
        .sheet(isPresented: $showSearch) {
            SearchView()
        }
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        Section {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Brand.gradient)
                    .shadow(color: Color(red: 20/255, green: 84/255, blue: 184/255).opacity(0.3),
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
