import SwiftUI
import UIKit

struct ProductDetailView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var product: Product

    @State private var stepAmount: String = "1"
    @State private var showingEdit = false
    @State private var showingMove = false
    @State private var showingAddUnit = false
    @State private var showingAddLot = false
    @State private var checkoutUnit: StockUnit?
    @State private var qrUnit: StockUnit?
    @State private var error: PresentableError?
    @State private var canEdit = true

    private var amount: Double { max(0, Double(stepAmount) ?? 0) }

    var body: some View {
        List {
            headerSection
            if canEdit { quickActionsSection }
            infoSection
            // Individual & lot products carry their QR on each unit/lot, so the
            // product-level label section is only for quantity products.
            if product.trackingMode == .quantity { labelsSection }
            if product.trackingMode == .individual { unitsSection }
            if product.trackingMode == .lot { lotsSection }
            historySection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(product.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if canEdit {
                    Menu {
                        Button { duplicateProduct() } label: {
                            Label(NSLocalizedString("この製品を複製", comment: ""), systemImage: "plus.square.on.square")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityIdentifier("productMenuButton")
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
        .sheet(item: $qrUnit) { unit in unitQRStudio(unit) }
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
                    Text(NSLocalizedString("数量", comment: "")).font(.title3)
                    Spacer()
                    TextField("1", text: $stepAmount)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .font(.title2.monospacedDigit()).frame(maxWidth: 90)
                        .accessibilityIdentifier("stepAmountField")
                }
                HStack(spacing: 12) {
                    Button {
                        change(.receive)
                    } label: {
                        Label(NSLocalizedString("入庫", comment: ""), systemImage: "plus.circle.fill")
                            .font(.title3.weight(.semibold)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("receiveButton")
                    Button {
                        change(.consume)
                    } label: {
                        Label(NSLocalizedString("出庫", comment: ""), systemImage: "minus.circle.fill")
                            .font(.title3.weight(.semibold)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).controlSize(.large)
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
        Section {
            if product.labelArray.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("QRラベルはまだありません", comment: "")).font(.subheadline)
                    Text(NSLocalizedString("先に発行した空のQRを「スキャン」から読み取り、この製品に割り当ててください。以降はスキャンするだけで入庫・出庫・移動ができます。", comment: ""))
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
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
        } header: {
            Text(NSLocalizedString("QRラベル", comment: ""))
        } footer: {
            if !product.labelArray.isEmpty {
                Text(NSLocalizedString("ラベルを開くと、メール送信・印刷ができます。", comment: ""))
            }
        }
    }

    private var unitsSection: some View {
        Section {
            if product.unitArray.isEmpty {
                Text(NSLocalizedString("個体がありません", comment: "")).foregroundColor(.secondary)
            }
            ForEach(product.unitArray) { unit in
                unitRow(unit)
            }
        } header: {
            Text(NSLocalizedString("個体", comment: ""))
        } footer: {
            Text(NSLocalizedString("個体にQRを付けるには、空のQRをスキャンして割り当てます。割り当て済みのQRをタップすると印刷・メール送信できます。", comment: ""))
        }
    }

    @ViewBuilder private func unitRow(_ unit: StockUnit) -> some View {
        let loan = container.inventory.currentLoan(for: unit)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
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
                if unit.labelArray.first != nil {
                    Button { qrUnit = unit } label: {
                        Image(systemName: "qrcode").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(NSLocalizedString("QRラベル", comment: "")))
                }
            }
            if canEdit {
                HStack(spacing: 10) {
                    if unit.status == .available {
                        Button(NSLocalizedString("貸出", comment: "")) { checkoutUnit = unit }
                            .buttonStyle(.bordered).controlSize(.small)
                        Button(NSLocalizedString("渡した", comment: "")) { giveAway(unit) }
                            .buttonStyle(.bordered).controlSize(.small).tint(.secondary)
                    } else if unit.status == .checkedOut {
                        Button(NSLocalizedString("返却", comment: "")) { unitAction(unit, .returned) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
        .padding(.vertical, 2)
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

    /// Create a new product like this one (same settings, no stock or history),
    /// then return to the list where the copy appears. Speeds up adding similar items.
    private func duplicateProduct() {
        let productID = product.objectID
        let result = container.performWrite { ctx in
            guard let src = try ctx.existingObject(with: productID) as? Product,
                  let project = src.project else { return }
            let copy = Product.make(in: ctx,
                                    name: String(format: NSLocalizedString("%@ のコピー", comment: ""), src.displayName),
                                    project: project,
                                    sku: "",
                                    unitName: src.unitLabel,
                                    trackingMode: src.trackingMode)
            copy.note = src.note
            copy.minimumStock = src.minimumStock
            copy.folder = src.folder
            copy.defaultLocation = src.defaultLocation
            container.router.assignChild(copy, toSameStoreAs: project, in: ctx)
        }
        switch result {
        case .success: Haptics.success(); dismiss()
        case .failure(let err): error = PresentableError(err)
        }
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

    /// Hand a sample over for good (given to a client / consumed) — leaves on-hand stock.
    private func giveAway(_ unit: StockUnit) {
        let unitID = unit.objectID
        let actor = settings.effectiveOperatorName
        _ = container.performWrite { ctx in
            guard let u = try ctx.existingObject(with: unitID) as? StockUnit else { return }
            container.inventory.retireUnit(u, actor: actor, note: NSLocalizedString("手渡し・配布", comment: ""), in: ctx)
        }
        Haptics.success()
    }

    /// The QR studio for a single unit's bound label (1 unit = 1 QR).
    @ViewBuilder private func unitQRStudio(_ unit: StockUnit) -> some View {
        if let code = unit.labelArray.first?.code {
            NavigationView {
                QRLabelStudioView(code: code,
                                  projectName: product.project?.displayName ?? "",
                                  targetName: "\(product.displayName) \(unit.displaySerial)")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(NSLocalizedString("閉じる", comment: "")) { qrUnit = nil }
                        }
                    }
            }
        }
    }
}

/// Adds an individually-tracked unit to a product.
struct AddUnitSheet: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let product: Product
    let project: Project
    @State private var count = 1
    @State private var serial = ""
    @State private var error: PresentableError?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Stepper(value: $count, in: 1...50) {
                        Text(String(format: NSLocalizedString("追加する数: %d", comment: ""), count))
                    }
                    if count == 1 {
                        TextField(NSLocalizedString("名前・番号（任意）", comment: ""), text: $serial)
                            .accessibilityIdentifier("serialField")
                    }
                } footer: {
                    Text(NSLocalizedString("個体にQRを付けるには、先に発行しておいた空のQRを「スキャン」から読み取って割り当ててください。", comment: ""))
                }
            }
            .navigationTitle(NSLocalizedString("個体を追加", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(NSLocalizedString("キャンセル", comment: "")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("追加", comment: "")) { add() }
                }
            }
            .errorAlert($error)
        }
    }

    private func add() {
        let trimmed = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = count
        let productID = product.objectID
        let projectID = project.objectID
        let actor = settings.effectiveOperatorName
        let result = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: productID) as? Product,
                  let proj = try ctx.existingObject(with: projectID) as? Project else { return }
            let start = p.unitArray.count
            for i in 0..<n {
                let label = (n == 1 && !trimmed.isEmpty) ? trimmed : "#\(start + i + 1)"
                let unit = StockUnit.make(in: ctx, serialNumber: label, product: p, project: proj, location: p.defaultLocation)
                container.router.assignChild(unit, toSameStoreAs: proj, in: ctx)
                container.inventory.registerUnit(unit, location: p.defaultLocation, actor: actor, in: ctx)
                // No QR is minted here. A label is attached only by scanning a
                // pre-printed blank QR and assigning it to this unit.
            }
        }
        switch result {
        case .success: dismiss()
        case .failure(let err): error = PresentableError(err)
        }
    }
}
