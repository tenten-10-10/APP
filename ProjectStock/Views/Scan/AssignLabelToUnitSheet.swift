import SwiftUI
import UIKit

/// Scan a pre-printed blank QR and bind it to a specific stock unit / lot, right
/// from that item's detail screen. Keeps QR labels flowing only through the
/// pre-print → scan → assign path, but scoped to one item so the user doesn't
/// have to pick it from a list.
struct AssignLabelToUnitSheet: View {
    @EnvironmentObject private var container: ServiceContainer
    @Environment(\.dismiss) private var dismiss
    @StateObject private var permission = CameraPermission()

    let unit: StockUnit
    var onAssigned: (() -> Void)? = nil

    @State private var torchOn = false
    @State private var zoom: CGFloat = 1
    @State private var error: PresentableError?
    @State private var busy = false

    var body: some View {
        NavigationView {
            ZStack {
                switch permission.status {
                case .authorized:
                    scannerLayer
                case .notDetermined:
                    prompt(message: NSLocalizedString("QRをスキャンするにはカメラの許可が必要です。", comment: ""),
                           action: NSLocalizedString("カメラを許可", comment: "")) { permission.request() }
                case .denied, .restricted:
                    prompt(message: NSLocalizedString("カメラへのアクセスが拒否されています。設定アプリから許可してください。", comment: ""),
                           action: NSLocalizedString("設定を開く", comment: "")) { openSettings() }
                case .unavailable:
                    EmptyStateView(systemImage: "camera.metering.unknown",
                                   title: NSLocalizedString("カメラを利用できません", comment: ""),
                                   message: NSLocalizedString("この端末ではスキャンできません。", comment: ""))
                }
            }
            .navigationTitle(NSLocalizedString("QRを割り当て", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("閉じる", comment: "")) { dismiss() }
                }
            }
            .onAppear { permission.refresh() }
            .errorAlert($error)
        }
    }

    private var scannerLayer: some View {
        ZStack {
            ScannerView(torchOn: $torchOn, zoom: $zoom, continuous: false,
                        paused: busy || error != nil,
                        onScan: handleScan, onError: { _ in })
                .ignoresSafeArea(edges: .bottom)

            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.9), lineWidth: 3)
                .frame(width: 220, height: 220)
                .accessibilityHidden(true)

            VStack {
                Text(NSLocalizedString("この個体に貼る空のQRをスキャンしてください", comment: ""))
                    .font(.headline).foregroundColor(.white).multilineTextAlignment(.center)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .padding(.top, 16)
                Spacer()
                Button { torchOn.toggle() } label: {
                    Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
                        .font(.title2).padding(14)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .accessibilityLabel(Text(NSLocalizedString("トーチ", comment: "")))
                .padding(.bottom, 28)
            }
        }
    }

    private func handleScan(_ raw: String) {
        guard !busy, error == nil else { return }
        let result = container.scanRouter.route(rawValue: raw, in: container.viewContext)
        switch result {
        case .unassigned(let alias):
            assign(alias)
        case .known(let alias):
            if alias.unit?.objectID == unit.objectID {
                Haptics.success(); onAssigned?(); dismiss()
            } else {
                Haptics.warning()
                error = PresentableError(message: NSLocalizedString("このQRは既に他の対象へ割り当て済みです。", comment: ""))
            }
        case .retired:
            Haptics.warning()
            error = PresentableError(message: NSLocalizedString("このQRは無効化されているため使用できません。", comment: ""))
        case .unknownAppCode:
            Haptics.warning()
            error = PresentableError(message: NSLocalizedString("未登録のQRです。先に「空のQRをまとめて発行」で作成してください。", comment: ""))
        case .foreign:
            Haptics.warning()
            error = PresentableError(message: NSLocalizedString("このQRはタナミルのコードではありません。", comment: ""))
        }
    }

    private func assign(_ alias: CodeAlias) {
        busy = true
        let aliasID = alias.objectID
        let unitID = unit.objectID
        let result = container.performWrite { ctx in
            guard let a = try ctx.existingObject(with: aliasID) as? CodeAlias,
                  let u = try ctx.existingObject(with: unitID) as? StockUnit else { return }
            try container.aliases.assign(alias: a, to: .unit(u))
            container.aliases.registerScan(alias: a)
            // 1個体=1QR: 付け直し（シール紛失時の再設定）では古いラベルを
            // 無効化する。紛失した印刷済みQRが後日出てきても退役済みなので、
            // 誤って同じ個体の「もう1枚のQR」として生き続けることがない。
            for old in u.activeLabels where old.objectID != a.objectID {
                container.aliases.retire(alias: old)
            }
        }
        busy = false
        switch result {
        case .success:
            Haptics.success(); onAssigned?(); dismiss()
        case .failure(let err):
            Haptics.warning(); error = PresentableError(err)
        }
    }

    private func prompt(message: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "qrcode.viewfinder").font(.system(size: 56)).foregroundColor(.secondary)
            Text(message).multilineTextAlignment(.center).padding(.horizontal)
            Button(action, action: perform).buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
