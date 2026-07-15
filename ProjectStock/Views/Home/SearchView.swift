import SwiftUI
import CoreData

/// Global search across products (by name/SKU), lots (by lot number), and
/// serial units (by serial number). Presented as a sheet from HomeView.
struct SearchView: View {
    @EnvironmentObject private var container: ServiceContainer

    // Entity-NAME-based requests (see HomeView): the `sortDescriptors:` convenience
    // form resolves via NSManagedObject.entity(), which returns nil under CloudKit
    // mirroring and crashes SwiftUI with "A fetch request must have an entity."
    @FetchRequest(fetchRequest: {
        let r = Product.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Product.name, ascending: true)]
        r.predicate = NSPredicate(format: "isArchived == NO")
        return r
    }(), animation: .default) private var products: FetchedResults<Product>

    @FetchRequest(fetchRequest: {
        let r = StockUnit.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \StockUnit.updatedAt, ascending: false)]
        return r
    }(), animation: .default) private var units: FetchedResults<StockUnit>

    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    // MARK: - Filtering

    private var matchedProducts: [Product] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return products.filter {
            $0.displayName.lowercased().contains(q) ||
            ($0.sku ?? "").lowercased().contains(q)
        }
    }

    private var matchedLots: [StockUnit] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return units.filter {
            $0.isLot &&
            ($0.lotNumber ?? "").lowercased().contains(q)
        }
    }

    private var matchedSerials: [StockUnit] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return units.filter {
            !$0.isLot &&
            $0.product != nil &&   // 行が生成できない一致は「シリアル番号」の空セクションになる
            !(($0.serialNumber ?? "").trimmingCharacters(in: .whitespaces).isEmpty) &&
            ($0.serialNumber ?? "").lowercased().contains(q)
        }
    }

    private var hasResults: Bool {
        !matchedProducts.isEmpty || !matchedLots.isEmpty || !matchedSerials.isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            Group {
                if searchText.isEmpty {
                    EmptyStateView(
                        systemImage: "magnifyingglass",
                        title: NSLocalizedString("検索", comment: ""),
                        message: NSLocalizedString("製品名、SKU、ロット番号、シリアル番号で検索できます。", comment: "")
                    )
                } else if !hasResults {
                    EmptyStateView(
                        systemImage: "magnifyingglass",
                        title: NSLocalizedString("結果なし", comment: ""),
                        message: NSLocalizedString("該当するアイテムが見つかりませんでした。", comment: "")
                    )
                } else {
                    resultList
                }
            }
            .navigationTitle(NSLocalizedString("検索", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("閉じる", comment: "")) { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("製品・ロット・シリアルを検索", comment: "")
        )
    }

    // MARK: - Result list

    private var resultList: some View {
        List {
            if !matchedProducts.isEmpty {
                Section(NSLocalizedString("製品", comment: "")) {
                    ForEach(matchedProducts) { product in
                        NavigationLink(destination: ProductDetailView(product: product)) {
                            ProductSearchRow(product: product, query: searchText)
                        }
                    }
                }
            }

            if !matchedLots.isEmpty {
                Section(NSLocalizedString("ロット", comment: "")) {
                    ForEach(matchedLots) { lot in
                        NavigationLink(destination: LotDetailView(lot: lot)) {
                            LotSearchRow(lot: lot, query: searchText)
                        }
                    }
                }
            }

            if !matchedSerials.isEmpty {
                Section(NSLocalizedString("シリアル番号", comment: "")) {
                    ForEach(matchedSerials) { unit in
                        // Navigate to the product detail (best available without a
                        // dedicated serial-unit detail screen)
                        if let product = unit.product {
                            NavigationLink(destination: ProductDetailView(product: product)) {
                                SerialSearchRow(unit: unit, query: searchText)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Row helpers

private struct ProductSearchRow: View {
    @ObservedObject var product: Product
    let query: String

    var body: some View {
        HStack(spacing: 10) {
            if product.photoThumbnail != nil {
                ProductThumbnail(data: product.photoThumbnail, size: 36)
            } else {
                Image(systemName: "shippingbox")
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(product.displayName)
                    .font(.subheadline).bold()
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let sku = product.sku, !sku.isEmpty {
                        Text("SKU: \(sku)")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    if let project = product.project {
                        Text(project.displayName)
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct LotSearchRow: View {
    @ObservedObject var lot: StockUnit
    let query: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.plus")
                .foregroundColor(.accentColor)
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
                    HStack(spacing: 4) {
                        Text(DateFormatters.day.string(from: expiry))
                            .font(.caption2)
                            .foregroundColor(lot.isExpired ? .red : .secondary)
                        ExpiryChip(unit: lot)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SerialSearchRow: View {
    @ObservedObject var unit: StockUnit
    let query: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "barcode")
                .foregroundColor(.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(unit.displaySerial)
                    .font(.subheadline).bold()
                    .lineLimit(1)
                if let product = unit.product {
                    Text(product.displayName)
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Text(unit.status.localizedTitle)
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
