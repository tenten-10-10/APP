import CoreData
import SwiftUI

/// Small pill showing a lot's expiry state.
struct ExpiryChip: View {
    let unit: StockUnit
    var body: some View {
        if unit.isExpired {
            chip(NSLocalizedString("期限切れ", comment: ""), .red)
        } else if unit.expiresSoon() {
            chip(NSLocalizedString("期限間近", comment: ""), .orange)
        }
    }
    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundColor(color)
    }
}

/// Adds a lot (batch) with an initial quantity and optional expiry date.
struct AddLotSheet: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var product: Product
    let project: Project

    @State private var lotNumber = ""
    @State private var quantity = ""
    @State private var hasExpiry = false
    @State private var expiry = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var locationID: NSManagedObjectID?
    @State private var error: PresentableError?

    var body: some View {
        NavigationView {
            Form {
                Section(NSLocalizedString("ロット", comment: "")) {
                    TextField(NSLocalizedString("ロット番号", comment: ""), text: $lotNumber)
                        .accessibilityIdentifier("lotNumberField")
                    HStack {
                        Text(NSLocalizedString("初期数量", comment: ""))
                        Spacer()
                        TextField("0", text: $quantity)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                            .accessibilityIdentifier("lotQuantityField")
                    }
                }
                Section {
                    Toggle(NSLocalizedString("有効期限を設定", comment: ""), isOn: $hasExpiry.animation())
                    if hasExpiry {
                        DatePicker(NSLocalizedString("有効期限", comment: ""), selection: $expiry, displayedComponents: [.date])
                    }
                } footer: {
                    if hasExpiry {
                        Text(NSLocalizedString("期限が近づくと一覧でお知らせします。", comment: ""))
                    }
                }
                Section(NSLocalizedString("保管場所", comment: "")) {
                    Picker(NSLocalizedString("場所", comment: ""), selection: $locationID) {
                        Text(NSLocalizedString("なし", comment: "")).tag(NSManagedObjectID?.none)
                        ForEach(project.locationArray) { Text($0.breadcrumb).tag(Optional($0.objectID)) }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("ロットを追加", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(NSLocalizedString("キャンセル", comment: "")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("追加", comment: "")) { save() }
                        .disabled(lotNumber.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("saveLotButton")
                }
            }
            .errorAlert($error)
        }
    }

    private func save() {
        let productID = product.objectID
        let actor = settings.effectiveOperatorName
        let lot = lotNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let qty = Double(quantity) ?? 0
        let due: Date? = hasExpiry ? expiry : nil
        let locID = locationID
        let result = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: productID) as? Product else { return }
            let loc = locID.flatMap { try? ctx.existingObject(with: $0) as? Location }
            _ = container.inventory.createLot(product: p, lotNumber: lot, quantity: qty,
                                              expiresAt: due, location: loc, actor: actor, in: ctx)
        }
        switch result {
        case .success:
            Haptics.success()
            // A new lot with an expiry date should (re)schedule its reminder.
            if hasExpiry {
                NotificationService.shared.requestAuthorization { _ in
                    container.refreshExpiryNotifications()
                }
            } else {
                container.refreshExpiryNotifications()
            }
            dismiss()
        case .failure(let err): error = PresentableError(err)
        }
    }
}

/// Detail / operations for a single lot: adjust quantity, manage its QR label,
/// and view history.
struct LotDetailView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var lot: StockUnit

    @State private var amountText = "1"
    @State private var error: PresentableError?
    @State private var canEdit = true

    private var amount: Double { max(0, Double(amountText) ?? 0) }

    var body: some View {
        List {
            Section {
                LabeledRow(title: NSLocalizedString("ロット番号", comment: ""), value: lot.lotNumberDisplay)
                HStack {
                    Text(NSLocalizedString("数量", comment: ""))
                    Spacer()
                    Text("\(lot.lotQuantity.quantityString) \(lot.product?.unitLabel ?? "")")
                        .foregroundColor(.secondary)
                }
                if let expiry = lot.expiresAt {
                    HStack {
                        Text(NSLocalizedString("有効期限", comment: ""))
                        Spacer()
                        Text(DateFormatters.day.string(from: expiry))
                            .foregroundColor(lot.isExpired ? .red : .secondary)
                        ExpiryChip(unit: lot)
                    }
                }
            }

            if canEdit {
                Section(NSLocalizedString("数量の更新", comment: "")) {
                    HStack {
                        Text(NSLocalizedString("数量", comment: ""))
                        Spacer()
                        TextField("1", text: $amountText).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).frame(maxWidth: 80)
                    }
                    HStack {
                        Button { change(+1) } label: { Label(NSLocalizedString("入庫", comment: ""), systemImage: "plus.circle") }
                            .buttonStyle(.borderedProminent)
                        Button { change(-1) } label: { Label(NSLocalizedString("出庫", comment: ""), systemImage: "minus.circle") }
                            .buttonStyle(.bordered)
                    }
                }
            }

            Section(NSLocalizedString("QRラベル", comment: "")) {
                if lot.activeLabels.isEmpty {
                    Text(NSLocalizedString("空のQRをスキャンしてこのロットに割り当てると、QRで管理できます。", comment: ""))
                        .font(.caption).foregroundColor(.secondary)
                }
                ForEach(lot.activeLabels) { label in
                    NavigationLink(destination: studio(for: label.code)) {
                        Label(label.code, systemImage: "qrcode")
                    }
                }
            }

            Section(NSLocalizedString("履歴", comment: "")) {
                let recent = Array(lot.eventArray.prefix(15))
                if recent.isEmpty { Text(NSLocalizedString("履歴がありません", comment: "")).foregroundColor(.secondary) }
                ForEach(recent) { EventRow(event: $0) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(lot.lotNumberDisplay)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { canEdit = lot.project.map { container.sharing.canEdit($0) } ?? true }
        .errorAlert($error)
    }

    private func studio(for code: String) -> some View {
        QRLabelStudioView(code: code,
                          projectName: lot.project?.displayName ?? "",
                          targetName: lot.lotNumberDisplay)
    }

    private func change(_ sign: Double) {
        guard amount > 0 else { return }
        let lotID = lot.objectID
        let actor = settings.effectiveOperatorName
        let result = container.performWrite { ctx in
            guard let l = try ctx.existingObject(with: lotID) as? StockUnit else { return }
            if sign > 0 { container.inventory.receiveToLot(l, quantity: amount, actor: actor, in: ctx) }
            else { container.inventory.consumeFromLot(l, quantity: amount, actor: actor, in: ctx) }
        }
        if case .failure(let err) = result { error = PresentableError(err) } else { Haptics.success() }
    }

}
