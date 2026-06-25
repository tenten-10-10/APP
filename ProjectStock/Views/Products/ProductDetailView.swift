import SwiftUI
import UIKit

struct ProductDetailView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var product: Product

    @State private var stepAmount: String = "1"
    @State private var showingEdit = false
    @State private var showingMove = false
    @State private var showingAddUnit = false
    @State private var showingAddLot = false
    @State private var checkoutUnit: StockUnit?
    @State private var error: PresentableError?
    @State private var canEdit = true

    private var amount: Double { max(0, Double(stepAmount) ?? 0) }

    var body: some View {
        List {
            headerSection
            if canEdit { quickActionsSection }
            infoSection
            labelsSection
            if product.trackingMode == .individual { unitsSection }
            if product.trackingMode == .lot { lotsSection }
            historySection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(product.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingEdit = true } label: { Image(systemName: "pencil") }
                        .accessibilityIdentifier("editProductButton")
                }
            }
        }
        .onAppear { canEdit = product.project.map { container.sharing.canEdit($0) } ?? true }
        .sheet(isPresented: $showingEdit) {
            if let project = product.project { ProductFormView(project: project, editing: product) }
        }
        .sheet(isPresented: $showingMove) {
            if let project = product.project {
                LocationPickerSheet(project: project, excluding: nil) { destination in move(to: destination) }
            }
        }
        .sheet(isPresented: $showingAddUnit) {
            if let project = product.project { AddUnitSheet(product: product, project: project) }
        }
        .sheet(item: $checkoutUnit) { unit in CheckoutSheet(unit: unit) }
        .sheet(isPresented: $showingAddLot) {
            if let project = product.project { AddLotSheet(product: product, project: project) }
        }
        .errorAlert($error)
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                if let data = product.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel(Text(NSLocalizedString("製品写真", comment: "")))
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground))
                        .frame(width: 72, height: 72)
                        .overlay(Image(systemName: "shippingbox").foregroundColor(.secondary))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName).font(.headline)
                    if let sku = product.sku, !sku.isEmpty { Text(sku).font(.caption).foregroundColor(.secondary) }
                    Text(product.trackingMode.localizedTitle).font(.caption2).foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Text("\(product.currentQuantity.quantityString) \(product.unitLabel)")
                            .font(.title3).bold().monospacedDigit()
                        if product.isLowStock { LowStockChip() }
                    }
                }
                Spacer()
            }
        }
    }

    private var quickActionsSection: some View {
        Section(NSLocalizedString("クイック操作", comment: "")) {
            if product.trackingMode == .quantity {
                HStack {
                    Text(NSLocalizedString("数量", comment: ""))
                    Spacer()
                    TextField("1", text: $stepAmount)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 80)
                        .accessibilityIdentifier("stepAmountField")
                }
                HStack(spacing: 12) {
                    Button {
                        change(.receive)
                    } label: { Label(NSLocalizedString("入庫", comment: ""), systemImage: "plus.circle.fill") }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("receiveButton")
                    Button {
                        change(.consume)
                    } label: { Label(NSLocalizedString("出庫", comment: ""), systemImage: "minus.circle.fill") }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("consumeButton")
                }
                .accessibilityHint(Text(NSLocalizedString("数量フィールドの値だけ在庫を増減します", comment: "")))
            }
            Button { showingMove = true } label: {
                Label(NSLocalizedString("場所を移動", comment: ""), systemImage: "arrow.left.arrow.right")
            }
            if product.trackingMode == .individual {
                Button { showingAddUnit = true } label: {
                    Label(NSLocalizedString("個体を追加", comment: ""), systemImage: "plus")
                }
            }
        }
    }

    private var infoSection: some View {
        Section(NSLocalizedString("状況", comment: "")) {
            LabeledRow(title: NSLocalizedString("最低在庫", comment: ""),
                       value: product.minimumStock == 0 ? "—" : product.minimumStock.quantityString)
            LabeledRow(title: NSLocalizedString("現在地", comment: ""),
                       value: product.currentLocation?.breadcrumb ?? "—")
            if let last = product.lastEvent {
                LabeledRow(title: NSLocalizedString("最終操作", comment: ""),
                           value: "\(last.eventType.localizedTitle) · \(DateFormatters.dateTime.string(from: last.occurredAt ?? Date()))")
            }
            if let scanned = lastScannedLabel {
                LabeledRow(title: NSLocalizedString("最終スキャン", comment: ""),
                           value: DateFormatters.dateTime.string(from: scanned))
            }
        }
    }

    private var labelsSection: some View {
        Section(NSLocalizedString("QRラベル", comment: "")) {
            ForEach(product.labelArray) { alias in
                NavigationLink(destination: studio(for: alias.code)) {
                    HStack {
                        Image(systemName: "qrcode")
                        VStack(alignment: .leading) {
                            Text(alias.code).font(.system(.callout, design: .monospaced))
                            if !alias.isActive {
                                Text(NSLocalizedString("無効", comment: "")).font(.caption2).foregroundColor(.red)
                            } else if alias.scanCount > 0 {
                                Text(String(format: NSLocalizedString("スキャン %d 回", comment: ""), alias.scanCount))
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            if canEdit {
                Button { createLabel() } label: {
                    Label(NSLocalizedString("ラベルを作成", comment: ""), systemImage: "plus")
                }
                .accessibilityIdentifier("createLabelButton")
            }
        }
    }

    private var unitsSection: some View {
        Section(NSLocalizedString("個体", comment: "")) {
            if product.unitArray.isEmpty {
                Text(NSLocalizedString("個体がありません", comment: "")).foregroundColor(.secondary)
            }
            ForEach(product.unitArray) { unit in
                unitRow(unit)
            }
        }
    }

    @ViewBuilder private func unitRow(_ unit: StockUnit) -> some View {
        let loan = container.inventory.currentLoan(for: unit)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(unit.displaySerial)
                HStack(spacing: 6) {
                    Text(unit.status.localizedTitle).font(.caption2).foregroundColor(.secondary)
                    if let borrower = loan?.borrower {
                        Text("· \(borrower)").font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                    if loan?.isOverdue == true { OverdueChip() }
                }
                if let due = loan?.dueAt {
                    Text(String(format: NSLocalizedString("期限: %@", comment: ""), DateFormatters.dateTime.string(from: due)))
                        .font(.caption2)
                        .foregroundColor(loan?.isOverdue == true ? .red : .secondary)
                }
            }
            Spacer()
            if canEdit {
                if unit.status == .available {
                    Button(NSLocalizedString("貸出", comment: "")) { checkoutUnit = unit }
                        .buttonStyle(.bordered).controlSize(.small)
                } else if unit.status == .checkedOut {
                    Button(NSLocalizedString("返却", comment: "")) { unitAction(unit, .returned) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
    }

    private var lotsSection: some View {
        Section(NSLocalizedString("ロット", comment: "")) {
            if product.lotArray.isEmpty {
                Text(NSLocalizedString("ロットがありません", comment: "")).foregroundColor(.secondary)
            }
            ForEach(product.lotArray) { lot in
                NavigationLink(destination: LotDetailView(lot: lot)) { lotRow(lot) }
            }
            if canEdit {
                Button { showingAddLot = true } label: {
                    Label(NSLocalizedString("ロットを追加", comment: ""), systemImage: "plus")
                }
                .accessibilityIdentifier("addLotButton")
            }
        }
    }

    @ViewBuilder private func lotRow(_ lot: StockUnit) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lot.lotNumberDisplay)
                if let expiry = lot.expiresAt {
                    Text(String(format: NSLocalizedString("期限: %@", comment: ""), DateFormatters.day.string(from: expiry)))
                        .font(.caption2).foregroundColor(lot.isExpired ? .red : .secondary)
                }
            }
            Spacer()
            ExpiryChip(unit: lot)
            Text("\(lot.lotQuantity.quantityString) \(product.unitLabel)")
                .font(.callout).foregroundColor(.secondary)
        }
    }

    private var historySection: some View {
        Section(NSLocalizedString("履歴", comment: "")) {
            let recent = Array(product.eventArray.prefix(15))
            if recent.isEmpty {
                Text(NSLocalizedString("履歴がありません", comment: "")).foregroundColor(.secondary)
            }
            ForEach(recent) { EventRow(event: $0) }
        }
    }

    // MARK: - Helpers

    private var lastScannedLabel: Date? {
        product.labelArray.compactMap { $0.lastScannedAt }.max()
    }

    private func studio(for code: String) -> some View {
        QRLabelStudioView(code: code,
                          projectName: product.project?.displayName ?? "",
                          targetName: product.displayName)
    }

    private enum QuantityAction { case receive, consume }

    private func change(_ action: QuantityAction) {
        guard amount > 0 else { return }
        let productID = product.objectID
        let actor = settings.effectiveOperatorName
        let location = product.currentLocation?.objectID
        let result = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: productID) as? Product else { return }
            let loc = location.flatMap { try? ctx.existingObject(with: $0) as? Location }
            switch action {
            case .receive: container.inventory.receive(product: p, quantity: amount, location: loc, actor: actor, in: ctx)
            case .consume: container.inventory.consume(product: p, quantity: amount, location: loc, actor: actor, in: ctx)
            }
        }
        if case .failure(let err) = result { error = PresentableError(err) } else { Haptics.success() }
    }

    private func move(to destination: Location) {
        let productID = product.objectID
        let destID = destination.objectID
        let from = product.currentLocation?.objectID
        let actor = settings.effectiveOperatorName
        _ = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: productID) as? Product,
                  let dst = try ctx.existingObject(with: destID) as? Location else { return }
            let src = from.flatMap { try? ctx.existingObject(with: $0) as? Location }
            p.defaultLocation = dst
            p.touch()
            container.inventory.transferQuantity(product: p, quantity: p.currentQuantity, from: src, to: dst, actor: actor, in: ctx)
        }
    }

    private func createLabel() {
        let productID = product.objectID
        let result = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: productID) as? Product, let project = p.project else { return }
            _ = try container.aliases.createAlias(for: .product(p), in: project, context: ctx)
        }
        if case .failure(let err) = result { error = PresentableError(err) }
    }

    private func unitAction(_ unit: StockUnit, _ type: InventoryEventType) {
        let unitID = unit.objectID
        let actor = settings.effectiveOperatorName
        _ = container.performWrite { ctx in
            guard let u = try ctx.existingObject(with: unitID) as? StockUnit else { return }
            switch type {
            case .checkout: container.inventory.checkout(unit: u, actor: actor, in: ctx)
            case .returned: container.inventory.returnUnit(u, to: u.location, actor: actor, in: ctx)
            default: break
            }
        }
        container.refreshLoanNotifications()
    }
}

/// Adds an individually-tracked unit to a product.
struct AddUnitSheet: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let product: Product
    let project: Project
    @State private var serial = ""
    @State private var error: PresentableError?

    var body: some View {
        NavigationView {
            Form {
                TextField(NSLocalizedString("シリアル番号", comment: ""), text: $serial)
                    .accessibilityIdentifier("serialField")
            }
            .navigationTitle(NSLocalizedString("個体を追加", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(NSLocalizedString("キャンセル", comment: "")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("追加", comment: "")) { add() }
                        .disabled(serial.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .errorAlert($error)
        }
    }

    private func add() {
        let trimmed = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        let productID = product.objectID
        let projectID = project.objectID
        let actor = settings.effectiveOperatorName
        let result = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: productID) as? Product,
                  let proj = try ctx.existingObject(with: projectID) as? Project else { return }
            let unit = StockUnit.make(in: ctx, serialNumber: trimmed, product: p, project: proj, location: p.defaultLocation)
            container.router.assignChild(unit, toSameStoreAs: proj, in: ctx)
            container.inventory.registerUnit(unit, location: p.defaultLocation, actor: actor, in: ctx)
        }
        switch result {
        case .success: dismiss()
        case .failure(let err): error = PresentableError(err)
        }
    }
}
