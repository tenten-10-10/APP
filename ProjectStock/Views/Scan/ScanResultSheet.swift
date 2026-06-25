import SwiftUI
import UIKit

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
            Text(NSLocalizedString("ProjectStock形式のコードですが、まだ同期されていないか、別のアカウントのものです。", comment: ""))
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
    @State private var error: PresentableError?

    var body: some View {
        List {
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
        if container.sharing.canEdit(unit.project) {
            Section(NSLocalizedString("操作", comment: "")) {
                if unit.status == .available {
                    Button(NSLocalizedString("貸出", comment: "")) { unitChange(unit, .checkout) }
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
        guard value > 0 else { return }
        let productID = product.objectID
        let actor = settings.effectiveOperatorName
        let loc = product.currentLocation?.objectID
        _ = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: productID) as? Product else { return }
            let location = loc.flatMap { try? ctx.existingObject(with: $0) as? Location }
            if sign > 0 { container.inventory.receive(product: p, quantity: value, location: location, actor: actor, in: ctx) }
            else { container.inventory.consume(product: p, quantity: value, location: location, actor: actor, in: ctx) }
        }
        Haptics.success()
    }

    private func unitChange(_ unit: StockUnit, _ type: InventoryEventType) {
        let unitID = unit.objectID
        let actor = settings.effectiveOperatorName
        _ = container.performWrite { ctx in
            guard let u = try ctx.existingObject(with: unitID) as? StockUnit else { return }
            if type == .checkout { container.inventory.checkout(unit: u, actor: actor, in: ctx) }
            else { container.inventory.returnUnit(u, to: u.location, actor: actor, in: ctx) }
        }
        Haptics.success()
    }

    private func moveProduct(to destination: Location) {
        guard let product = alias.product else { return }
        let productID = product.objectID
        let destID = destination.objectID
        let from = product.currentLocation?.objectID
        let actor = settings.effectiveOperatorName
        _ = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: productID) as? Product,
                  let dst = try ctx.existingObject(with: destID) as? Location else { return }
            let src = from.flatMap { try? ctx.existingObject(with: $0) as? Location }
            p.defaultLocation = dst; p.touch()
            container.inventory.transferQuantity(product: p, quantity: p.currentQuantity, from: src, to: dst, actor: actor, in: ctx)
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
