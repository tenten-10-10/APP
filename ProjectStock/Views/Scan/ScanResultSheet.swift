import SwiftUI
import UIKit
import CoreData

/// Presents the outcome of a scan (spec §8) with the relevant quick actions.
struct ScanResultSheet: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let outcome: ScanOutcome

    var body: some View {
        NavigationView {
            Group {
                switch outcome {
                case .known(let alias):       KnownTargetView(alias: alias)
                case .unassigned(let alias):  AssignmentView(alias: alias)
                case .retired(let alias):     RetiredCodeView(alias: alias)
                case .unknownAppCode(let code): unknownView(code)
                case .foreign(let value):     foreignView(value)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(NSLocalizedString("閉じる", comment: "")) { dismiss() } } }
        }
    }

    private func unknownView(_ code: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle").font(.system(size: 48)).foregroundColor(.secondary)
            Text(NSLocalizedString("このコードはこの端末で見つかりません", comment: "")).font(.headline)
            Text(NSLocalizedString("タナミル形式のコードですが、まだ同期されていないか、別のアカウントのものです。iCloud同期の完了を少し待ってから、もう一度スキャンしてみてください。", comment: ""))
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            Text(code).font(.system(.callout, design: .monospaced))
            Button(NSLocalizedString("コードをコピー", comment: "")) { UIPasteboard.general.string = code }
        }
        .padding().navigationTitle(NSLocalizedString("未知のコード", comment: ""))
    }

    private func foreignView(_ value: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle").font(.system(size: 48)).foregroundColor(.secondary)
            Text(NSLocalizedString("対象外のQRです", comment: "")).font(.headline)
            Text(NSLocalizedString("タナミルで発行したQRではありません。管理したい品物には「空のQRをまとめて発行」で作ったラベルを貼ってください。", comment: ""))
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            Text(value).font(.system(.callout, design: .monospaced)).lineLimit(4)
            Button(NSLocalizedString("コピー", comment: "")) { UIPasteboard.general.string = value }
        }
        .padding().navigationTitle(NSLocalizedString("対象外", comment: ""))
    }
}

/// Quick-action surface for an assigned label (spec §8 quick actions).
private struct KnownTargetView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var alias: CodeAlias
    @State private var amount = "1"
    @State private var showingMove = false
    @State private var showingCheckout = false
    @State private var error: PresentableError?
    /// Inline confirmation shown after 入庫/出庫/移動/返却 — haptics alone don't
    /// tell a first-time user whether the action was actually recorded.
    @State private var feedback: String?
    @State private var feedbackIsError = false
    /// The event just recorded from this sheet, so a slip of the finger can be
    /// undone RIGHT HERE (before this, the only path was hunting the row down
    /// in the 活動 tab).
    @State private var undoableEventID: NSManagedObjectID?

    var body: some View {
        List {
            if let feedback {
                Section {
                    Label(feedback, systemImage: feedbackIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundColor(feedbackIsError ? .orange : .green)
                    if !feedbackIsError && undoableEventID != nil {
                        Button {
                            undoLastAction()
                        } label: {
                            Label(NSLocalizedString("今の操作を取り消す", comment: ""), systemImage: "arrow.uturn.backward")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            switch alias.targetType {
            case .product:
                if let product = alias.product { productActions(product) }
            case .unit:
                if let unit = alias.unit { unitActions(unit) }
            case .location:
                if let location = alias.location { locationActions(location) }
            case .unassigned:
                Text(NSLocalizedString("未割当", comment: ""))
            }
        }
        .navigationTitle(NSLocalizedString("スキャン結果", comment: ""))
        .errorAlert($error)
        .sheet(isPresented: $showingMove) {
            if let project = alias.project {
                LocationPickerSheet(project: project, excluding: nil) { dest in moveProduct(to: dest) }
            }
        }
        .sheet(isPresented: $showingCheckout) {
            if let unit = alias.unit { CheckoutSheet(unit: unit) }
        }
    }

    @ViewBuilder private func productActions(_ product: Product) -> some View {
        Section {
            NavigationLink(destination: ProductDetailView(product: product)) {
                VStack(alignment: .leading) {
                    Text(product.displayName).font(.headline)
                    Text("\(product.currentQuantity.quantityString) \(product.unitLabel)").foregroundColor(.secondary)
                }
            }
        }
        if container.sharing.canEdit(product.project) && product.trackingMode == .quantity {
            Section(NSLocalizedString("数量", comment: "")) {
                HStack {
                    Text(NSLocalizedString("数量", comment: ""))
                    Spacer()
                    TextField("1", text: $amount).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 80)
                }
                HStack {
                    Button { quantity(product, +1) } label: { Label(NSLocalizedString("入庫", comment: ""), systemImage: "plus.circle") }
                        .buttonStyle(.borderedProminent)
                    Button { quantity(product, -1) } label: { Label(NSLocalizedString("出庫", comment: ""), systemImage: "minus.circle") }
                        .buttonStyle(.bordered)
                }
                Button { showingMove = true } label: { Label(NSLocalizedString("場所を移動", comment: ""), systemImage: "arrow.left.arrow.right") }
            }
        }
    }

    @ViewBuilder private func unitActions(_ unit: StockUnit) -> some View {
        if unit.isLot { lotActions(unit) } else { serialUnitActions(unit) }
    }

    @ViewBuilder private func lotActions(_ lot: StockUnit) -> some View {
        Section {
            NavigationLink(destination: LotDetailView(lot: lot)) {
                VStack(alignment: .leading) {
                    Text(lot.lotNumberDisplay).font(.headline)
                    Text("\(lot.lotQuantity.quantityString) \(lot.product?.unitLabel ?? "")")
                        .foregroundColor(.secondary)
                }
            }
            if let expiry = lot.expiresAt {
                HStack {
                    Text(NSLocalizedString("有効期限", comment: ""))
                    Spacer()
                    Text(DateFormatters.day.string(from: expiry)).foregroundColor(lot.isExpired ? .red : .secondary)
                    ExpiryChip(unit: lot)
                }
            }
        }
        if container.sharing.canEdit(lot.project) {
            Section(NSLocalizedString("数量", comment: "")) {
                HStack {
                    Text(NSLocalizedString("数量", comment: ""))
                    Spacer()
                    TextField("1", text: $amount).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 80)
                }
                HStack {
                    Button { lotChange(lot, +1) } label: { Label(NSLocalizedString("入庫", comment: ""), systemImage: "plus.circle") }
                        .buttonStyle(.borderedProminent)
                    Button { lotChange(lot, -1) } label: { Label(NSLocalizedString("出庫", comment: ""), systemImage: "minus.circle") }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder private func serialUnitActions(_ unit: StockUnit) -> some View {
        Section {
            if let product = unit.product {
                NavigationLink(destination: ProductDetailView(product: product)) {
                    VStack(alignment: .leading) {
                        Text(unit.displaySerial).font(.headline)
                        Text(unit.status.localizedTitle).foregroundColor(.secondary)
                    }
                }
            }
        }
        if let loan = container.inventory.currentLoan(for: unit) {
            Section(NSLocalizedString("貸出情報", comment: "")) {
                LoanDetailRows(loan: loan)
            }
        }
        if container.sharing.canEdit(unit.project) {
            Section(NSLocalizedString("操作", comment: "")) {
                if unit.status == .available {
                    Button(NSLocalizedString("貸出", comment: "")) { showingCheckout = true }
                } else if unit.status == .checkedOut {
                    Button(NSLocalizedString("返却", comment: "")) { unitChange(unit, .returned) }
                }
            }
        }
    }

    @ViewBuilder private func locationActions(_ location: Location) -> some View {
        Section {
            NavigationLink(destination: LocationDetailView(location: location,
                                                           canEdit: container.sharing.canEdit(location.project))) {
                VStack(alignment: .leading) {
                    Text(location.displayName).font(.headline)
                    Text(location.breadcrumb).foregroundColor(.secondary).font(.caption)
                }
            }
        }
    }

    private func quantity(_ product: Product, _ sign: Double) {
        let value = (Double(amount) ?? 0)
        guard value > 0 else {
            Haptics.warning()
            feedback = NSLocalizedString("数量に1以上の数を入力してください", comment: "")
            feedbackIsError = true
            return
        }
        let productID = product.objectID
        let actor = settings.effectiveOperatorName
        let loc = product.currentLocation?.objectID
        var recorded: InventoryEvent?
        _ = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: productID) as? Product else { return }
            let location = loc.flatMap { try? ctx.existingObject(with: $0) as? Location }
            if sign > 0 { recorded = container.inventory.receive(product: p, quantity: value, location: location, actor: actor, in: ctx) }
            else { recorded = container.inventory.consume(product: p, quantity: value, location: location, actor: actor, in: ctx) }
        }
        Haptics.success()
        feedback = String(format: sign > 0
            ? NSLocalizedString("＋%@ 入庫を記録しました", comment: "")
            : NSLocalizedString("−%@ 出庫を記録しました", comment: ""), value.quantityString)
        feedbackIsError = false
        undoableEventID = recorded?.objectID
    }

    private func lotChange(_ lot: StockUnit, _ sign: Double) {
        let value = Double(amount) ?? 0
        guard value > 0 else {
            Haptics.warning()
            feedback = NSLocalizedString("数量に1以上の数を入力してください", comment: "")
            feedbackIsError = true
            return
        }
        let lotID = lot.objectID
        let actor = settings.effectiveOperatorName
        var recorded: InventoryEvent?
        _ = container.performWrite { ctx in
            guard let l = try ctx.existingObject(with: lotID) as? StockUnit else { return }
            if sign > 0 { recorded = container.inventory.receiveToLot(l, quantity: value, actor: actor, in: ctx) }
            else { recorded = container.inventory.consumeFromLot(l, quantity: value, actor: actor, in: ctx) }
        }
        Haptics.success()
        feedback = String(format: sign > 0
            ? NSLocalizedString("＋%@ 入庫を記録しました", comment: "")
            : NSLocalizedString("−%@ 出庫を記録しました", comment: ""), value.quantityString)
        feedbackIsError = false
        undoableEventID = recorded?.objectID
    }

    private func unitChange(_ unit: StockUnit, _ type: InventoryEventType) {
        let unitID = unit.objectID
        let actor = settings.effectiveOperatorName
        var recorded: InventoryEvent?
        _ = container.performWrite { ctx in
            guard let u = try ctx.existingObject(with: unitID) as? StockUnit else { return }
            if type == .checkout { recorded = container.inventory.checkout(unit: u, actor: actor, in: ctx) }
            else { recorded = container.inventory.returnUnit(u, to: u.location, actor: actor, in: ctx) }
        }
        Haptics.success()
        feedback = type == .checkout
            ? NSLocalizedString("貸出を記録しました", comment: "")
            : NSLocalizedString("返却を記録しました", comment: "")
        feedbackIsError = false
        undoableEventID = recorded?.objectID
        container.refreshLoanNotifications()
    }

    private func moveProduct(to destination: Location) {
        guard let product = alias.product else { return }
        let productID = product.objectID
        let destID = destination.objectID
        let from = product.currentLocation?.objectID
        let actor = settings.effectiveOperatorName
        var recorded: InventoryEvent?
        _ = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: productID) as? Product,
                  let dst = try ctx.existingObject(with: destID) as? Location else { return }
            let src = from.flatMap { try? ctx.existingObject(with: $0) as? Location }
            p.defaultLocation = dst; p.touch()
            recorded = container.inventory.transferQuantity(product: p, quantity: p.currentQuantity, from: src, to: dst, actor: actor, in: ctx)
        }
        Haptics.success()
        feedback = String(format: NSLocalizedString("「%@」へ移動しました", comment: ""), destination.displayName)
        feedbackIsError = false
        undoableEventID = recorded?.objectID
    }

    /// Reverse the event this sheet just recorded (逆仕訳). The original stays
    /// in the ledger; the correction is added on top — same mechanics as the
    /// 活動タブの「訂正」, just reachable at the moment the mistake happened.
    private func undoLastAction() {
        guard let eventID = undoableEventID else { return }
        let actor = settings.effectiveOperatorName
        let result = container.performWrite { ctx in
            guard let original = try ctx.existingObject(with: eventID) as? InventoryEvent else { return }
            container.inventory.reverse(event: original, actor: actor,
                                        note: NSLocalizedString("スキャン画面からの取り消し", comment: ""), in: ctx)
        }
        switch result {
        case .success:
            Haptics.success()
            undoableEventID = nil
            feedback = NSLocalizedString("取り消しました", comment: "")
            feedbackIsError = false
            container.refreshLoanNotifications()
        case .failure(let err):
            error = PresentableError(err)
        }
    }
}

/// Shows why a code is inactive and offers to mint a replacement (spec §8 case 2).
private struct RetiredCodeView: View {
    @EnvironmentObject private var container: ServiceContainer
    @ObservedObject var alias: CodeAlias
    @State private var error: PresentableError?
    @State private var reissued: String?

    var body: some View {
        List {
            Section {
                Label(NSLocalizedString("このラベルは無効化されています", comment: ""), systemImage: "nosign")
                    .foregroundColor(.red)
                if let date = alias.retiredAt {
                    LabeledRow(title: NSLocalizedString("無効化日時", comment: ""), value: DateFormatters.dateTime.string(from: date))
                }
                LabeledRow(title: NSLocalizedString("元の対象", comment: ""), value: alias.resolvedTargetName)
            }
            if let reissued {
                Section { Label(String(format: NSLocalizedString("新しいラベル %@ を発行しました", comment: ""), reissued), systemImage: "checkmark.circle") }
            } else if canReissue {
                Section {
                    Button { reissue() } label: { Label(NSLocalizedString("同じ対象で再発行", comment: ""), systemImage: "arrow.clockwise") }
                }
            }
        }
        .navigationTitle(NSLocalizedString("無効なコード", comment: ""))
        .errorAlert($error)
    }

    private var canReissue: Bool {
        alias.product != nil || alias.unit != nil || alias.location != nil
    }

    private func reissue() {
        let aliasID = alias.objectID
        let result = container.performWrite { ctx in
            guard let a = try ctx.existingObject(with: aliasID) as? CodeAlias, let project = a.project else { return }
            let target: CodeAliasService.AliasTarget
            if let p = a.product { target = .product(p) }
            else if let u = a.unit { target = .unit(u) }
            else if let l = a.location { target = .location(l) }
            else { return }
            let newAlias = try container.aliases.createAlias(for: target, in: project, context: ctx)
            DispatchQueue.main.async { reissued = newAlias.code }
        }
        if case .failure(let err) = result { error = PresentableError(err) }
    }
}
