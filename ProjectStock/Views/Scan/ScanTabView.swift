import SwiftUI
import UIKit

struct ScanTabView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var permission = CameraPermission()

    @State private var torchOn = false
    @State private var zoom: CGFloat = 1
    @State private var outcome: ScanOutcomeBox?
    @State private var foreignValue: String?

    var body: some View {
        ZStack {
            switch permission.status {
            case .authorized:
                scannerLayer
            case .notDetermined:
                permissionPrompt(message: NSLocalizedString("QRをスキャンするにはカメラの許可が必要です。", comment: ""),
                                 action: NSLocalizedString("カメラを許可", comment: "")) { permission.request() }
            case .denied, .restricted:
                permissionPrompt(message: NSLocalizedString("カメラへのアクセスが拒否されています。設定アプリから許可してください。", comment: ""),
                                 action: NSLocalizedString("設定を開く", comment: "")) { openSettings() }
            case .unavailable:
                EmptyStateView(systemImage: "camera.metering.unknown",
                               title: NSLocalizedString("カメラを利用できません", comment: ""),
                               message: NSLocalizedString("この端末ではスキャンできません。手動でコードを入力してください。", comment: ""))
            }
        }
        .navigationTitle(NSLocalizedString("スキャン", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                NavigationLink(destination: LoansView()) {
                    Label(NSLocalizedString("貸出中", comment: ""), systemImage: "person.crop.circle.badge.arrow.up")
                }
                .accessibilityIdentifier("loansButton")
                NavigationLink(destination: StocktakeStartView()) {
                    Label(NSLocalizedString("棚卸し", comment: ""), systemImage: "list.clipboard")
                }
            }
        }
        .onAppear { permission.refresh() }
        .sheet(item: $outcome) { box in
            ScanResultSheet(outcome: box.outcome)
        }
        .alert(item: Binding(get: { foreignValue.map { PresentableError(message: $0) } },
                             set: { _ in foreignValue = nil })) { presentable in
            Alert(title: Text(NSLocalizedString("対象外のQR", comment: "")),
                  message: Text(NSLocalizedString("このQRはProjectStockのコードではありません。", comment: "")),
                  primaryButton: .default(Text(NSLocalizedString("コピー", comment: ""))) {
                      UIPasteboard.general.string = presentable.message
                  },
                  secondaryButton: .cancel(Text(NSLocalizedString("閉じる", comment: ""))))
        }
    }

    private var scannerLayer: some View {
        ZStack {
            ScannerView(torchOn: $torchOn, zoom: $zoom, continuous: false,
                        onScan: handleScan, onError: { _ in })
                .ignoresSafeArea(edges: .bottom)

            // Reticle.
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.9), lineWidth: 3)
                .frame(width: 220, height: 220)
                .accessibilityHidden(true)

            VStack {
                Spacer()
                HStack(spacing: 24) {
                    Button { torchOn.toggle() } label: {
                        Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
                            .font(.title2).padding(14)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .accessibilityLabel(Text(NSLocalizedString("トーチ", comment: "")))

                    VStack {
                        Image(systemName: "plus.magnifyingglass").font(.caption)
                        Slider(value: $zoom, in: 1...6).frame(width: 140)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .accessibilityLabel(Text(NSLocalizedString("ズーム", comment: "")))
                }
                .padding(.bottom, 28)
            }
        }
    }

    private func permissionPrompt(message: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "qrcode.viewfinder").font(.system(size: 56)).foregroundColor(.secondary)
            Text(message).multilineTextAlignment(.center).padding(.horizontal)
            Button(action, action: perform).buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func handleScan(_ raw: String) {
        let result = container.scanRouter.route(rawValue: raw, in: container.viewContext)
        switch result {
        case .known(let alias), .unassigned(let alias), .retired(let alias):
            registerScan(alias)
            Haptics.success()
            outcome = ScanOutcomeBox(outcome: result)
        case .unknownAppCode:
            Haptics.warning()
            outcome = ScanOutcomeBox(outcome: result)
        case .foreign(let value):
            Haptics.warning()
            foreignValue = value
        }
    }

    private func registerScan(_ alias: CodeAlias) {
        let aliasID = alias.objectID
        _ = container.performWrite { ctx in
            guard let a = try ctx.existingObject(with: aliasID) as? CodeAlias else { return }
            container.aliases.registerScan(alias: a)
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Identifiable wrapper so a `ScanOutcome` can drive `.sheet(item:)`.
struct ScanOutcomeBox: Identifiable {
    let id = UUID()
    let outcome: ScanOutcome
}
