import SwiftUI
import CoreData
import UIKit

/// ハンディターミナルモード（ベータ）: JAN/ITF バーコードとQRを連続スキャンして
/// 照会・入庫・出庫をその場で記録する全画面モード。設計原則は「1スキャン=1確定、
/// 確認タップゼロ、ただし全操作が即時Undo可能」。スキャンタブの「ハンディ」から
/// 起動する（＝カメラ許可済みの文脈でのみ開く）。
struct HandyModeView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var entitlements: EntitlementService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var session = HandySession()

    @State private var mode: HandyMode = .lookup   // 必ず照会で起動（誤記帳防止）
    @State private var amount = 1
    @State private var torchOn = false
    @State private var zoom: CGFloat = 1
    @State private var card: HandyCard?
    @State private var flashColor: Color?
    @State private var ignoredCodes: Set<String> = []
    @State private var registerBox: HandyRegisterBox?
    @State private var productBox: HandyProductBox?
    @State private var showHistory = false
    @State private var showAmountPad = false
    @State private var confirmClose = false
    @State private var showPaywall = false
    @State private var error: PresentableError?

    var body: some View {
        content
            .sheet(item: $registerBox) { box in
                HandyRegisterSheet(code: box.code, mode: mode, amount: amount, session: session,
                                   onCard: { card = $0 })
            }
            .background(historySheetLayer)
            .background(productSheetLayer)
            .background(amountPadLayer)
            .background(closeConfirmLayer)
            .errorAlert($error)
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder private var content: some View {
        if !EntitlementService.handyEnabled {
            unavailableView(NSLocalizedString("ハンディモードは現在利用できません。", comment: ""))
        } else if EntitlementService.handyPremium && !entitlements.hasTeamFeatures {
            premiumGate
        } else {
            mainStack
        }
    }

    private var mainStack: some View {
        VStack(spacing: 0) {
            stateBand
            scannerArea
            controls
        }
        .background(Color.black.ignoresSafeArea())
    }

    /// A sheet/alert is up — stop delivering scans behind it.
    private var scanPaused: Bool {
        registerBox != nil || productBox != nil || showHistory || showAmountPad || confirmClose || showPaywall
    }

    // MARK: - State band (全面モード色 = 4チャネル冗長告知の1つ)

    private var stateBand: some View {
        HStack(spacing: 12) {
            Button { requestClose() } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text(NSLocalizedString("閉じる", comment: "")))
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: mode.systemImage)
                Text(mode.title).fontWeight(.heavy)
                if amount > 1 && mode != .lookup {
                    Text("×\(amount)")
                        .font(.headline.weight(.heavy))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.25)))
                }
                Text(NSLocalizedString("ベータ", comment: ""))
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.22)))
            }
            .font(.title2)
            .foregroundColor(.white)
            Spacer()
            Button { torchOn.toggle() } label: {
                Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text(NSLocalizedString("ライト", comment: "")))
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(mode.color.ignoresSafeArea(edges: .top))
        .animation(.easeInOut(duration: 0.15), value: mode)
    }

    // MARK: - Scanner + result card

    private var scannerArea: some View {
        ZStack {
            ScannerView(torchOn: $torchOn, zoom: $zoom, continuous: true,
                        paused: scanPaused, oneDimensional: true, debounce: 1.3,
                        onScan: handleScan, onError: { _ in })
            RoundedRectangle(cornerRadius: 14)
                .stroke((flashColor ?? .clear), lineWidth: 6)
                .padding(4)
                .allowsHitTesting(false)
            VStack {
                Text(NSLocalizedString("バーコード（JAN・ITF）またはQRを読み取ります", comment: ""))
                    .font(.footnote.weight(.semibold)).foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .padding(.top, 10)
                Spacer()
                if let card { HandyCardView(card: card, onAction: handleCardAction) }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    // MARK: - Bottom controls (親指ゾーン)

    private var controls: some View {
        VStack(spacing: 10) {
            modeButtons
            if mode != .lookup { amountChips }
            bottomRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color.black)
    }

    private var modeButtons: some View {
        HStack(spacing: 8) {
            ForEach(HandyMode.allCases) { m in
                Button {
                    guard m != mode else { return }
                    mode = m
                    amount = 1   // 倍率の掛けっぱなし事故をモード切替で必ず解消
                    Haptics.tap()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: m.systemImage)
                        Text(m.title).fontWeight(.bold)
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(m == mode ? m.color : Color.white.opacity(0.12)))
                    .foregroundColor(.white)
                }
                .accessibilityIdentifier("handyMode_\(m.rawValue)")
            }
        }
    }

    private var amountChips: some View {
        HStack(spacing: 8) {
            ForEach([1, 5, 10], id: \.self) { n in
                Button {
                    amount = n
                    Haptics.tap()
                } label: {
                    Text("×\(n)")
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(amount == n ? Color.white.opacity(0.9) : Color.white.opacity(0.12)))
                        .foregroundColor(amount == n ? .black : .white)
                }
            }
            Button {
                showAmountPad = true
            } label: {
                Image(systemName: "keyboard")
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.12)))
                    .foregroundColor(.white)
            }
            .accessibilityLabel(Text(NSLocalizedString("数量を入力", comment: "")))
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 8) {
            Button { undoLast() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                    Text(undoLabel).lineLimit(1)
                }
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.12)))
                .foregroundColor(session.undoable == nil ? .gray : .white)
            }
            .disabled(session.undoable == nil)
            Button { showHistory = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                    Text(String(format: NSLocalizedString("履歴 %d", comment: ""), session.entries.count))
                }
                .font(.footnote.weight(.semibold))
                .frame(width: 110, height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.12)))
                .foregroundColor(.white)
            }
        }
    }

    private var undoLabel: String {
        if let e = session.undoable {
            return String(format: NSLocalizedString("元に戻す（%@ %@）", comment: ""), e.title, e.detail)
        }
        return NSLocalizedString("元に戻す", comment: "")
    }

    // MARK: - Scan handling

    private func handleScan(_ raw: String) {
        guard !scanPaused else { return }
        if let digits = BarcodeCode.normalize(raw) {
            handleBarcode(digits)
            return
        }
        let outcome = container.scanRouter.route(rawValue: raw, in: viewContext)
        switch outcome {
        case .known(let alias):
            if let product = alias.product { act(on: product) }
            else if let unit = alias.unit { showUnitCard(unit) }
            else if let location = alias.location {
                infoCard(title: location.displayName,
                         subtitle: NSLocalizedString("保管場所・コンテナのQRです", comment: ""))
            } else {
                warnCard(NSLocalizedString("割当先が見つかりません", comment: ""), subtitle: alias.code)
            }
        case .unassigned:
            warnCard(NSLocalizedString("未割当のQRです", comment: ""),
                     subtitle: NSLocalizedString("スキャンタブで品物を登録できます", comment: ""))
        case .retired:
            warnCard(NSLocalizedString("無効化されたQRです", comment: ""), subtitle: nil)
        case .unknownAppCode(let code):
            warnCard(NSLocalizedString("未知のコードです", comment: ""), subtitle: code)
        case .foreign(let value):
            warnCard(NSLocalizedString("対象外のコードです", comment: ""), subtitle: String(value.prefix(40)))
        }
    }

    private func handleBarcode(_ digits: String) {
        if ignoredCodes.contains(digits) { return }   // 無視したコードはセッション中サイレント
        if let alias = container.aliases.findAlias(forCode: digits, in: viewContext) {
            if let product = alias.product { act(on: product) }
            else if let unit = alias.unit { showUnitCard(unit) }
            else {
                warnCard(NSLocalizedString("このバーコードの割当先が見つかりません", comment: ""), subtitle: digits)
            }
        } else {
            HandySound.lookup()
            Haptics.warning()
            flash(.orange)
            card = HandyCard(kind: .warning,
                             title: NSLocalizedString("未登録のバーコードです", comment: ""),
                             subtitle: "\(BarcodeCode.typeName(for: digits))  \(digits)",
                             actions: [.init(label: NSLocalizedString("登録する", comment: ""), action: .register(code: digits)),
                                       .init(label: NSLocalizedString("無視", comment: ""), action: .ignore(code: digits))])
        }
    }

    private func act(on product: Product) {
        switch mode {
        case .lookup:
            showLookupCard(product)
        case .receive, .consume:
            performQuantityOp(on: product)
        }
    }

    private func showLookupCard(_ product: Product) {
        HandySound.lookup()
        Haptics.tap()
        flash(HandyMode.lookup.color)
        var lines: [String] = []
        lines.append("\(product.currentQuantity.quantityString) \(product.unitLabel)・\(product.trackingMode.localizedTitle)")
        if let loc = product.defaultLocation { lines.append(loc.breadcrumb) }
        if let proj = product.project { lines.append(proj.displayName) }
        card = HandyCard(kind: .info, title: product.displayName,
                         subtitle: lines.joined(separator: "\n"),
                         actions: [.init(label: NSLocalizedString("開く", comment: ""), action: .openProduct(product.objectID))])
    }

    private func showUnitCard(_ unit: StockUnit) {
        HandySound.lookup()
        Haptics.tap()
        flash(HandyMode.lookup.color)
        var subtitle = unit.status.localizedTitle
        if let loan = container.inventory.currentLoan(for: unit) {
            subtitle = String(format: NSLocalizedString("貸出中: %@", comment: ""), loan.borrowerDisplay)
        }
        if mode != .lookup {
            subtitle += "\n" + NSLocalizedString("個体の貸出・返却は製品画面から操作してください", comment: "")
        }
        var actions: [HandyCard.CardButton] = []
        if let product = unit.product {
            actions.append(.init(label: NSLocalizedString("開く", comment: ""), action: .openProduct(product.objectID)))
        }
        card = HandyCard(kind: .info,
                         title: "\(unit.displaySerial)（\(unit.product?.displayName ?? "")）",
                         subtitle: subtitle, actions: actions)
    }

    private func performQuantityOp(on product: Product) {
        guard let project = product.project, container.sharing.canEdit(project) else {
            errorCard(NSLocalizedString("閲覧のみのプロジェクトのため記録できません", comment: ""),
                      subtitle: product.displayName)
            return
        }
        guard product.trackingMode == .quantity else {
            let hint = product.trackingMode == .individual
                ? NSLocalizedString("個体管理の製品です。製品画面から操作してください", comment: "")
                : NSLocalizedString("ロット管理の製品です。製品画面から操作してください", comment: "")
            HandySound.error()
            Haptics.warning()
            flash(.orange)
            card = HandyCard(kind: .warning, title: product.displayName, subtitle: hint,
                             actions: [.init(label: NSLocalizedString("開く", comment: ""), action: .openProduct(product.objectID))])
            return
        }
        let qty = Double(amount)
        let before = product.currentQuantity
        let isReceive = (mode == .receive)
        if !isReceive && before < qty {
            errorCard(String(format: NSLocalizedString("在庫が足りません（残 %@）", comment: ""), before.quantityString),
                      subtitle: product.displayName)
            return
        }
        let productID = product.objectID
        let actor = settings.effectiveOperatorName
        let name = product.displayName
        let unitLabel = product.unitLabel
        var eventID: NSManagedObjectID?
        let result = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: productID) as? Product else { return }
            let note = NSLocalizedString("ハンディ", comment: "")
            let event = isReceive
                ? container.inventory.receive(product: p, quantity: qty, location: p.defaultLocation,
                                              actor: actor, note: note, in: ctx)
                : container.inventory.consume(product: p, quantity: qty, location: p.defaultLocation,
                                              actor: actor, note: note, in: ctx)
            try ctx.obtainPermanentIDs(for: [event])
            eventID = event.objectID
        }
        switch result {
        case .success:
            let after = before + (isReceive ? qty : -qty)
            let detail = (isReceive ? "+" : "−") + qty.quantityString + " " + mode.title
            session.add(HandyEntry(eventID: eventID, title: name, detail: detail))
            isReceive ? HandySound.receive() : HandySound.consume()
            Haptics.success()
            flash(mode.color)
            card = HandyCard(kind: .success, title: name,
                             subtitle: "\(detail)  ｜  \(before.quantityString) → \(after.quantityString) \(unitLabel)")
        case .failure(let err):
            error = PresentableError(err)
        }
    }

    // MARK: - Undo

    private func undoLast() {
        guard let entry = session.undoable else { return }
        undo(entry)
    }

    func undo(_ entry: HandyEntry) {
        guard let eventID = entry.eventID else { return }
        let actor = settings.effectiveOperatorName
        let result = container.performWrite { ctx in
            guard let event = try ctx.existingObject(with: eventID) as? InventoryEvent else { return }
            _ = container.inventory.reverse(event: event, actor: actor,
                                            note: NSLocalizedString("ハンディで取消", comment: ""), in: ctx)
        }
        switch result {
        case .success:
            session.markReversed(entry.id)
            Haptics.success()
            card = HandyCard(kind: .info, title: NSLocalizedString("取り消しました", comment: ""),
                             subtitle: "\(entry.title)  \(entry.detail)")
        case .failure(let err):
            error = PresentableError(err)
        }
    }

    // MARK: - Card actions / feedback

    private func handleCardAction(_ action: HandyCard.Action) {
        switch action {
        case .register(let code):
            registerBox = HandyRegisterBox(code: code)
        case .ignore(let code):
            ignoredCodes.insert(code)
            card = nil
        case .openProduct(let oid):
            productBox = HandyProductBox(objectID: oid)
        }
    }

    private func infoCard(title: String, subtitle: String?) {
        HandySound.lookup(); Haptics.tap(); flash(HandyMode.lookup.color)
        card = HandyCard(kind: .info, title: title, subtitle: subtitle)
    }

    private func warnCard(_ title: String, subtitle: String?) {
        HandySound.error(); Haptics.warning(); flash(.orange)
        card = HandyCard(kind: .warning, title: title, subtitle: subtitle)
    }

    private func errorCard(_ title: String, subtitle: String?) {
        HandySound.error(); Haptics.error(); flash(.red)
        card = HandyCard(kind: .error, title: title, subtitle: subtitle)
    }

    private func flash(_ color: Color) {
        flashColor = color
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            flashColor = nil
        }
    }

    // MARK: - Close / gates

    private func requestClose() {
        if session.entries.contains(where: { !$0.reversed && $0.eventID != nil }) {
            confirmClose = true
        } else {
            dismiss()
        }
    }

    private var closeConfirmLayer: some View {
        Color.clear.alert(isPresented: $confirmClose) {
            Alert(title: Text(NSLocalizedString("ハンディを終了しますか？", comment: "")),
                  message: Text(String(format: NSLocalizedString("このセッション: 入庫 %d件 ／ 出庫 %d件（すべて記録済みです）", comment: ""),
                                       session.receiveCount, session.consumeCount)),
                  primaryButton: .default(Text(NSLocalizedString("終了する", comment: ""))) { dismiss() },
                  secondaryButton: .cancel(Text(NSLocalizedString("続ける", comment: ""))))
        }
    }

    private var historySheetLayer: some View {
        Color.clear.sheet(isPresented: $showHistory) {
            HandyHistorySheet(session: session, onUndo: { undo($0) })
        }
    }

    private var productSheetLayer: some View {
        Color.clear.sheet(item: $productBox) { box in
            HandyProductSheet(objectID: box.objectID)
        }
    }

    private var amountPadLayer: some View {
        Color.clear.sheet(isPresented: $showAmountPad) {
            HandyAmountSheet(amount: $amount)
        }
    }

    private var premiumGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "barcode.viewfinder").font(.system(size: 56)).foregroundColor(.secondary)
            Text(NSLocalizedString("ハンディモードの無料ベータは終了しました", comment: ""))
                .font(.headline).multilineTextAlignment(.center)
            Text(NSLocalizedString("引き続き使うには タナミル チーム への加入が必要です。", comment: ""))
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button(NSLocalizedString("プランを見る", comment: "")) { showPaywall = true }
                .buttonStyle(.borderedProminent)
            Button(NSLocalizedString("閉じる", comment: "")) { dismiss() }
        }
        .padding()
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private func unavailableView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(message).multilineTextAlignment(.center)
            Button(NSLocalizedString("閉じる", comment: "")) { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Identifiable boxes

struct HandyRegisterBox: Identifiable {
    let id = UUID()
    let code: String
}

struct HandyProductBox: Identifiable {
    let id = UUID()
    let objectID: NSManagedObjectID
}

// MARK: - Result card view

struct HandyCardView: View {
    let card: HandyCard
    let onAction: (HandyCard.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(card.tint).frame(width: 10, height: 10)
                Text(card.title).font(.headline).foregroundColor(.white).lineLimit(2)
                Spacer(minLength: 0)
            }
            if let subtitle = card.subtitle {
                Text(subtitle)
                    .font(.subheadline).foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !card.actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(card.actions) { item in
                        Button {
                            onAction(item.action)
                        } label: {
                            Text(item.label)
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.22)))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(card.tint, lineWidth: 2))
    }
}

// MARK: - History sheet

struct HandyHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: HandySession
    let onUndo: (HandyEntry) -> Void

    var body: some View {
        NavigationView {
            List {
                if session.entries.isEmpty {
                    Text(NSLocalizedString("まだ操作がありません", comment: "")).foregroundColor(.secondary)
                }
                ForEach(session.entries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).strikethrough(entry.reversed)
                            Text("\(entry.detail) ・ \(DateFormatters.short.string(from: entry.date))")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if entry.reversed {
                            Text(NSLocalizedString("取消済み", comment: "")).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if !entry.reversed && entry.eventID != nil {
                            Button(NSLocalizedString("取消", comment: "")) { onUndo(entry) }.tint(.orange)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("このセッションの操作", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("閉じる", comment: "")) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Product bridge sheet

struct HandyProductSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    let objectID: NSManagedObjectID

    var body: some View {
        NavigationView {
            if let product = try? viewContext.existingObject(with: objectID) as? Product {
                ProductDetailView(product: product)
            } else {
                Text(NSLocalizedString("製品が見つかりません", comment: "")).foregroundColor(.secondary)
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Amount pad sheet

struct HandyAmountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var amount: Int
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField(NSLocalizedString("数量（1〜999）", comment: ""), text: $text)
                        .keyboardType(.numberPad)
                        .focused($focused)
                } footer: {
                    Text(NSLocalizedString("次のスキャンから、1回の読み取りでこの数量を記録します。", comment: ""))
                }
            }
            .navigationTitle(NSLocalizedString("数量を入力", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("キャンセル", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("決定", comment: "")) {
                        if let n = Int(text), (1...999).contains(n) { amount = n }
                        dismiss()
                    }
                    .disabled(Int(text).map { !(1...999).contains($0) } ?? true)
                }
            }
            .onAppear {
                text = "\(amount)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true }
            }
        }
    }
}
