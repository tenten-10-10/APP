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
    // A scanned invite QR (share link) is handled in place, not routed as an
    // inventory code.
    @State private var joining = false
    @State private var joinMessage: String?
    @State private var joinSucceeded = false

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
                  message: Text(NSLocalizedString("このQRはタナミルのコードではありません。", comment: "")),
                  primaryButton: .default(Text(NSLocalizedString("コピー", comment: ""))) {
                      UIPasteboard.general.string = presentable.message
                  },
                  secondaryButton: .cancel(Text(NSLocalizedString("閉じる", comment: ""))))
        }
        // The join-result alert lives on a SEPARATE (background) view node, so it
        // never contends with the "対象外" alert above — iOS 15 can silently drop
        // one of two alerts attached to the same view.
        .background(
            Color.clear
                .alert(item: Binding(get: { joinMessage.map { PresentableError(message: $0) } },
                                     set: { _ in joinMessage = nil })) { presentable in
                    Alert(title: Text(joinSucceeded
                                      ? NSLocalizedString("共有に参加しました", comment: "")
                                      : NSLocalizedString("共有に参加できませんでした", comment: "")),
                          message: Text(presentable.message),
                          dismissButton: .default(Text(NSLocalizedString("OK", comment: ""))))
                }
        )
    }

    /// A result is on screen — the camera must not keep scanning behind it.
    private var resultShowing: Bool { outcome != nil || foreignValue != nil || joining || joinMessage != nil }

    private var scannerLayer: some View {
        ZStack {
            ScannerView(torchOn: $torchOn, zoom: $zoom, continuous: false,
                        paused: resultShowing,
                        onScan: handleScan, onError: { _ in })
                .ignoresSafeArea(edges: .bottom)

            // Reticle.
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.9), lineWidth: 3)
                .frame(width: 220, height: 220)
                .accessibilityHidden(true)

            // Plain-language guidance at the top.
            VStack {
                Text(NSLocalizedString("QRコードを枠の中に入れてください", comment: ""))
                    .font(.headline).foregroundColor(.white).multilineTextAlignment(.center)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .padding(.top, 16)
                Spacer()
            }

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
        // Belt and braces: a frame already in flight when the session pauses
        // must not replace the result the user is looking at.
        guard !resultShowing else { return }
        // An invite QR (t.l0l0.app/join?s=… or a raw icloud.com/share link) is a
        // share invitation, not an inventory code — so scanning it with タナミル's
        // OWN reader joins the shared project instead of showing "対象外".
        if let shareURL = joinShareURL(from: raw) {
            joining = true
            container.sharing.joinShare(from: shareURL) { result in
                joining = false
                switch result {
                case .success:
                    joinSucceeded = true
                    Haptics.success()
                    joinMessage = NSLocalizedString("共有プロジェクトに参加しました。同期が終わると「プロジェクト」一覧に表示されます。", comment: "")
                case .failure(let err):
                    joinSucceeded = false
                    Haptics.warning()
                    joinMessage = err.localizedDescription
                }
            }
            return
        }
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

    /// If the scanned string is a share invitation — our own wrapper link
    /// (`t.l0l0.app/join?s=…`) or a raw `icloud.com/share/…` link — return the
    /// iCloud share URL to accept. Inventory codes (`t.l0l0.app/<code>`) return
    /// nil and route normally.
    private func joinShareURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let inner = RootTabView.shareURL(fromJoinLink: url) {
            return inner
        }
        return CloudSharingService.extractShareURL(from: trimmed)
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
