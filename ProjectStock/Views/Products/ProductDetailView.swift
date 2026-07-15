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
    @State private var assignUnit: StockUnit?
    @State private var deletingUnit: StockUnit?
    @State private var renamingUnit: StockUnit?
    @State private var editingLoanUnit: StockUnit?
    @State private var deletingLot: StockUnit?
    @State private var unassigningLabel: CodeAlias?
    @State private var retiringLabel: CodeAlias?
    @State private var confirmingProductDelete = false
    @State private var error: PresentableError?
    @State private var canEdit = true

    private var amount: Double { max(0, Double(stepAmount) ?? 0) }

    /// Remote kill-switch (app-config.json) so deletion can be paused without
    /// an app release if a sync-related loss bug is ever found in the field.
    private var deleteEnabled: Bool { RemoteConfig.shared.bool("deleteEnabled", default: true) }

    // The body is layered into computed properties: one flat expression with
    // this many sections + sheets + alerts blows the type-checker's budget
    // ("unable to type-check this expression in reasonable time").
    var body: some View {
        alertedList
            .alert(NSLocalizedString("QRの割り当てを解除しますか？", comment: ""),
                   isPresented: unassignPresented,
                   presenting: unassigningLabel) { alias in
                Button(NSLocalizedString("解除する", comment: "")) {
                    unassignLabel(alias); unassigningLabel = nil
                }
                Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) { unassigningLabel = nil }
            } message: { alias in
                Text(String(format: NSLocalizedString("%@ は空のQRに戻り、スキャンして別の品物・場所に割り当て直せます。", comment: ""), alias.code))
            }
            .alert(NSLocalizedString("QRを無効化しますか？", comment: ""),
                   isPresented: retirePresented,
                   presenting: retiringLabel) { alias in
                Button(NSLocalizedString("無効化する", comment: ""), role: .destructive) {
                    retireLabel(alias); retiringLabel = nil
                }
                Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) { retiringLabel = nil }
            } message: { alias in
                Text(String(format: NSLocalizedString("%@ は読み取っても使えなくなります（元に戻せません）。シールを紛失・破棄したときに使ってください。", comment: ""), alias.code))
            }
            .errorAlert($error)
    }

    private var deletingUnitPresented: Binding<Bool> {
        Binding(get: { deletingUnit != nil }, set: { if !$0 { deletingUnit = nil } })
    }
    private var deletingLotPresented: Binding<Bool> {
        Binding(get: { deletingLot != nil }, set: { if !$0 { deletingLot = nil } })
    }
    private var unassignPresented: Binding<Bool> {
        Binding(get: { unassigningLabel != nil }, set: { if !$0 { unassigningLabel = nil } })
    }
    private var retirePresented: Binding<Bool> {
        Binding(get: { retiringLabel != nil }, set: { if !$0 { retiringLabel = nil } })
    }

    private var alertedList: some View {
        sheetedList
            .alert(NSLocalizedString("個体を削除しますか？", comment: ""),
                   isPresented: deletingUnitPresented,
                   presenting: deletingUnit) { unit in
                Button(NSLocalizedString("削除", comment: ""), role: .destructive) {
                    deleteUnit(unit); deletingUnit = nil
                }
                Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) { deletingUnit = nil }
            } message: { unit in
                Text(String(format: NSLocalizedString("「%@」をリストから完全に削除します。割り当てていたQRラベルは空に戻り、別の品物に再利用できます（操作履歴には削除の記録が残ります）。", comment: ""), unit.displaySerial))
            }
            .alert(NSLocalizedString("製品を削除しますか？", comment: ""), isPresented: $confirmingProductDelete) {
                Button(NSLocalizedString("削除", comment: ""), role: .destructive) { deleteProduct() }
                Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) {}
            } message: {
                Text(String(format: NSLocalizedString("「%@」と、その個体・在庫数がすべて削除されます。割り当てていたQRラベルは空に戻り、別の品物に再利用できます（操作履歴には削除の記録が残ります）。", comment: ""), product.displayName))
            }
            .alert(NSLocalizedString("ロットを削除しますか？", comment: ""),
                   isPresented: deletingLotPresented,
                   presenting: deletingLot) { lot in
                Button(NSLocalizedString("削除", comment: ""), role: .destructive) {
                    deleteLot(lot); deletingLot = nil
                }
                Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) { deletingLot = nil }
            } message: { lot in
                Text(String(format: NSLocalizedString("ロット「%@」を数量ごと削除します。割り当てていたQRラベルは空に戻り、再利用できます（操作履歴には削除の記録が残ります）。", comment: ""), lot.lotNumberDisplay))
            }
    }

    private var sheetedList: some View {
        itemSheetedList
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
            .sheet(isPresented: $showingAddLot) {
                if let project = product.project { AddLotSheet(product: product, project: project) }
            }
    }

    private var itemSheetedList: some View {
        decoratedList
            .sheet(item: $checkoutUnit) { unit in CheckoutSheet(unit: unit) }
            .sheet(item: $qrUnit) { unit in unitQRStudio(unit) }
            .sheet(item: $assignUnit) { unit in AssignLabelToUnitSheet(unit: unit) }
            .sheet(item: $renamingUnit) { unit in
                RenameSheet(title: NSLocalizedString("名前を変更", comment: ""),
                            placeholder: NSLocalizedString("名前・番号", comment: ""),
                            initialText: (unit.serialNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                            footer: NSLocalizedString("QRの割り当て・貸出・履歴はそのまま引き継がれます。", comment: "")) { newName in
                    renameUnit(unit, to: newName)
                }
            }
            .sheet(item: $editingLoanUnit) { unit in LoanEditSheet(unit: unit) }
    }

    private var decoratedList: some View {
        contentList
            .listStyle(.insetGrouped)
            .navigationTitle(product.displayName)
            .keyboardDoneBar()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear { canEdit = product.project.map { container.sharing.canEdit($0) } ?? true }
    }

    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if canEdit {
                Menu {
                    Button { duplicateProduct() } label: {
                        Label(NSLocalizedString("この製品を複製", comment: ""), systemImage: "plus.square.on.square")
                    }
                    if deleteEnabled {
                        Button(role: .destructive) { requestDeleteProduct() } label: {
                            Label(NSLocalizedString("この製品を削除", comment: ""), systemImage: "trash")
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityIdentifier("productMenuButton")
                    .accessibilityLabel(Text(NSLocalizedString("その他の操作", comment: "")))
                Button { showingEdit = true } label: { Image(systemName: "pencil") }
                    .accessibilityIdentifier("editProductButton")
                    .accessibilityLabel(Text(NSLocalizedString("編集", comment: "")))
            }
        }
    }

    private var contentList: some View {
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
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                if let data = product.photoThumbnail, let image = UIImage(data: data) {
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
                if alias.isActive {
                    NavigationLink(destination: studio(for: alias.code)) {
                        HStack {
                            Image(systemName: "qrcode")
                            VStack(alignment: .leading) {
                                Text(alias.code).font(.system(.callout, design: .monospaced))
                                if alias.scanCount > 0 {
                                    Text(String(format: NSLocalizedString("スキャン %d 回", comment: ""), alias.scanCount))
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if canEdit {
                            Button(role: .destructive) { retiringLabel = alias } label: {
                                Label(NSLocalizedString("無効化", comment: ""), systemImage: "nosign")
                            }
                            Button { unassigningLabel = alias } label: {
                                Label(NSLocalizedString("割り当て解除", comment: ""), systemImage: "minus.circle")
                            }
                            .tint(.orange)
                        }
                    }
                    .contextMenu {
                        if canEdit {
                            Button { unassigningLabel = alias } label: {
                                Label(NSLocalizedString("割り当て解除（空のQRに戻す）", comment: ""), systemImage: "minus.circle")
                            }
                            Button(role: .destructive) { retiringLabel = alias } label: {
                                Label(NSLocalizedString("無効化（紛失・破棄したとき）", comment: ""), systemImage: "nosign")
                            }
                        }
                    }
                } else {
                    // 無効化済み: 印刷・共有させない（貼っても読めないラベルを
                    // 量産する行き止まりを防ぐ）。表示のみ。
                    HStack {
                        Image(systemName: "qrcode")
                        Text(alias.code).font(.system(.callout, design: .monospaced))
                        Spacer()
                        Text(NSLocalizedString("無効", comment: "")).font(.caption2).foregroundColor(.red)
                    }
                    .foregroundColor(.secondary)
                }
            }
        } header: {
            Text(NSLocalizedString("QRラベル", comment: ""))
        } footer: {
            if !product.labelArray.isEmpty {
                Text(NSLocalizedString("ラベルを開くと、メール送信・印刷ができます。行を左にスワイプすると、割り当て解除（別の品物へ使い回す）や無効化ができます。", comment: ""))
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
        // 貸出中かどうかは「台帳（＝活動タブと同じ）」を正とする。個体の
        // キャッシュ済み status は、真夜中(0:00)に記録された貸出より後の
        // タイムスタンプを持つ初期登録に負けて .available に巻き戻ることが
        // あり、そうなると貸出中の個体から返却ボタンが消えてしまう。台帳に
        // 開いた貸出があれば status に関わらず「貸出中」として扱う。
        let isOnLoan = loan != nil || unit.status == .checkedOut
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(unit.displaySerial)
                    HStack(spacing: 6) {
                        Text(isOnLoan ? UnitStatus.checkedOut.localizedTitle : unit.status.localizedTitle)
                            .font(.caption2).foregroundColor(.secondary)
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
                if unit.activeLabels.first != nil {
                    Button { qrUnit = unit } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "qrcode").font(.title2)
                            Text(NSLocalizedString("QRあり", comment: "")).font(.caption2)
                        }
                        .foregroundColor(Brand.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(NSLocalizedString("QRラベルを開く", comment: "")))
                } else if canEdit {
                    Button { assignUnit = unit } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "qrcode.viewfinder").font(.title2)
                            Text(NSLocalizedString("QRを割り当て", comment: "")).font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("assignUnitQRButton")
                } else {
                    Text(NSLocalizedString("QRなし", comment: ""))
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            if canEdit {
                HStack(spacing: 10) {
                    if isOnLoan {
                        Button(NSLocalizedString("返却", comment: "")) { unitAction(unit, .returned) }
                            .buttonStyle(.bordered).controlSize(.small)
                    } else if unit.status == .available {
                        Button(NSLocalizedString("貸出", comment: "")) { checkoutUnit = unit }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    if !isOnLoan && deleteEnabled {
                        Button(NSLocalizedString("削除", comment: "")) { requestDeleteUnit(unit) }
                            .buttonStyle(.bordered).controlSize(.small).tint(.red)
                            .accessibilityIdentifier("deleteUnitButton")
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canEdit && deleteEnabled {
                Button(role: .destructive) { requestDeleteUnit(unit) } label: {
                    Label(NSLocalizedString("削除", comment: ""), systemImage: "trash")
                }
            }
        }
        .contextMenu {
            if canEdit {
                Button { renamingUnit = unit } label: {
                    Label(NSLocalizedString("名前を変更", comment: ""), systemImage: "pencil")
                }
                if isOnLoan {
                    Button { unitAction(unit, .returned) } label: {
                        Label(NSLocalizedString("返却", comment: ""), systemImage: "arrow.uturn.left")
                    }
                    Button { editingLoanUnit = unit } label: {
                        Label(NSLocalizedString("期限・借り手を変更", comment: ""), systemImage: "calendar.badge.clock")
                    }
                } else if unit.status == .available {
                    Button { checkoutUnit = unit } label: {
                        Label(NSLocalizedString("貸出", comment: ""), systemImage: "person.badge.clock")
                    }
                }
                if unit.activeLabels.first != nil {
                    // イレギュラー用なので長押しメニューの奥に: 貸出から戻って
                    // きたらQRシールが剥がれて無くなっていた、を救う再設定。
                    // 新しい空QRを割り当てると古いコードは自動で無効化される。
                    Button { assignUnit = unit } label: {
                        Label(NSLocalizedString("QRを付け直す（紛失時）", comment: ""), systemImage: "qrcode.viewfinder")
                    }
                }
                if deleteEnabled {
                    Button(role: .destructive) { requestDeleteUnit(unit) } label: {
                        Label(NSLocalizedString("削除", comment: ""), systemImage: "trash")
                    }
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if canEdit && deleteEnabled {
                            Button(role: .destructive) { deletingLot = lot } label: {
                                Label(NSLocalizedString("削除", comment: ""), systemImage: "trash")
                            }
                        }
                    }
                    .contextMenu {
                        if canEdit && deleteEnabled {
                            Button(role: .destructive) { deletingLot = lot } label: {
                                Label(NSLocalizedString("削除", comment: ""), systemImage: "trash")
                            }
                        }
                    }
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

    @ViewBuilder private var historySection: some View {
        let recent = Array(product.eventArray.prefix(15))
        if recent.isEmpty {
            Section(NSLocalizedString("履歴", comment: "")) {
                Text(NSLocalizedString("履歴がありません", comment: "")).foregroundColor(.secondary)
            }
        } else {
            Section {
                EmptyView()
            } header: {
                Text(NSLocalizedString("履歴", comment: ""))
            } footer: {
                if canEdit {
                    Text(NSLocalizedString("間違えた記録は、行を左にスワイプして「訂正」で打ち消せます。", comment: ""))
                }
            }
            EventListView(events: recent, onCorrect: canEdit ? correctEvent : nil)
        }
    }

    /// Reverse a mistaken event right here — hunting for the same row in the
    /// 活動 tab was the only way before.
    private func correctEvent(_ event: InventoryEvent) {
        let eventID = event.objectID
        let actor = settings.effectiveOperatorName
        if let project = event.project, !container.sharing.canEdit(project) {
            error = PresentableError(AppError.readOnlyProject); return
        }
        let result = container.performWrite { ctx in
            guard let original = try ctx.existingObject(with: eventID) as? InventoryEvent else { return }
            container.inventory.reverse(event: original, actor: actor,
                                        note: NSLocalizedString("製品画面からの訂正", comment: ""), in: ctx)
        }
        if case .failure(let err) = result { error = PresentableError(err) } else { Haptics.success() }
        container.refreshLoanNotifications()
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

    /// Deleting the product while units are out on loan would orphan the
    /// loans, so demand returns first.
    private func requestDeleteProduct() {
        if product.unitArray.contains(where: { $0.status == .checkedOut || container.inventory.currentLoan(for: $0) != nil }) {
            error = PresentableError(AppError.underlying(NSLocalizedString("貸出中の個体がある製品は削除できません。先に「返却」してから削除してください。", comment: "")))
        } else {
            confirmingProductDelete = true
        }
    }

    private func deleteProduct() {
        let productID = product.objectID
        let actor = settings.effectiveOperatorName
        let result = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: productID) as? Product else { return }
            container.inventory.deleteProduct(p, actor: actor, in: ctx)
        }
        switch result {
        case .success: Haptics.success(); dismiss()
        case .failure(let err): error = PresentableError(err)
        }
    }

    /// Deleting a checked-out unit would orphan its loan, so demand a return
    /// first; everything else goes through the confirmation alert.
    private func requestDeleteUnit(_ unit: StockUnit) {
        // status のキャッシュが巻き戻っていても台帳に開いた貸出があれば削除させない
        if unit.status == .checkedOut || container.inventory.currentLoan(for: unit) != nil {
            error = PresentableError(AppError.underlying(NSLocalizedString("貸出中の個体は削除できません。先に「返却」してから削除してください。", comment: "")))
        } else {
            deletingUnit = unit
        }
    }

    private func deleteUnit(_ unit: StockUnit) {
        let unitID = unit.objectID
        let actor = settings.effectiveOperatorName
        let result = container.performWrite { ctx in
            guard let u = try ctx.existingObject(with: unitID) as? StockUnit else { return }
            container.inventory.deleteUnit(u, actor: actor, in: ctx)
        }
        if case .failure(let err) = result { error = PresentableError(err) } else { Haptics.success() }
    }

    private func deleteLot(_ lot: StockUnit) {
        let lotID = lot.objectID
        let actor = settings.effectiveOperatorName
        let result = container.performWrite { ctx in
            guard let l = try ctx.existingObject(with: lotID) as? StockUnit else { return }
            container.inventory.deleteUnit(l, actor: actor, in: ctx)
        }
        if case .failure(let err) = result { error = PresentableError(err) } else { Haptics.success() }
        container.refreshExpiryNotifications()
    }

    private func renameUnit(_ unit: StockUnit, to newName: String) {
        let unitID = unit.objectID
        let result = container.performWrite { ctx in
            guard let u = try ctx.existingObject(with: unitID) as? StockUnit else { return }
            container.inventory.renameUnit(u, to: newName)
        }
        if case .failure(let err) = result { error = PresentableError(err) } else { Haptics.success() }
        container.refreshLoanNotifications()   // 通知本文に個体名が入るため
    }

    private func unassignLabel(_ alias: CodeAlias) {
        let aliasID = alias.objectID
        let result = container.performWrite { ctx in
            guard let a = try ctx.existingObject(with: aliasID) as? CodeAlias else { return }
            container.aliases.unassign(alias: a)
        }
        if case .failure(let err) = result { error = PresentableError(err) } else { Haptics.success() }
    }

    private func retireLabel(_ alias: CodeAlias) {
        let aliasID = alias.objectID
        let result = container.performWrite { ctx in
            guard let a = try ctx.existingObject(with: aliasID) as? CodeAlias else { return }
            container.aliases.retire(alias: a)
        }
        if case .failure(let err) = result { error = PresentableError(err) } else { Haptics.success() }
    }

    /// The QR studio for a single unit's bound label (1 unit = 1 QR).
    @ViewBuilder private func unitQRStudio(_ unit: StockUnit) -> some View {
        if let code = (unit.activeLabels.first ?? unit.labelArray.first)?.code {
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
            .keyboardDoneBar()
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
