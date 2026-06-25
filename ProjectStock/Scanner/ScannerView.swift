import SwiftUI

/// SwiftUI bridge around `BarcodeScannerController`. In UI-test runs it renders
/// a deterministic mock instead of a live camera (spec §8: モック入力).
struct ScannerView: View {
    @Binding var torchOn: Bool
    @Binding var zoom: CGFloat
    var continuous: Bool
    var onScan: (String) -> Void
    var onError: (String) -> Void

    var body: some View {
        if AppConfig.isUITesting {
            MockScannerView(onScan: onScan)
        } else {
            CameraScannerRepresentable(torchOn: $torchOn, zoom: $zoom,
                                       continuous: continuous, onScan: onScan, onError: onError)
        }
    }
}

private struct CameraScannerRepresentable: UIViewControllerRepresentable {
    @Binding var torchOn: Bool
    @Binding var zoom: CGFloat
    var continuous: Bool
    var onScan: (String) -> Void
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerController {
        let controller = BarcodeScannerController()
        controller.onScan = onScan
        controller.onSessionError = onError
        controller.allowsRepeatAfterDebounce = continuous
        return controller
    }

    func updateUIViewController(_ controller: BarcodeScannerController, context: Context) {
        controller.allowsRepeatAfterDebounce = continuous
        controller.setTorch(on: torchOn)
        controller.setZoom(factor: zoom)
        if !continuous { /* single-shot resets handled by parent */ }
    }
}

/// Deterministic stand-in used during UI tests and SwiftUI previews. Exposes
/// accessibility identifiers so XCUITest can drive scans.
struct MockScannerView: View {
    var onScan: (String) -> Void
    @State private var manualCode: String = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 64))
                    .foregroundColor(.white)
                Text("モックスキャナ")
                    .foregroundColor(.white)
                TextField("コードを入力", text: $manualCode)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .padding(.horizontal, 40)
                    .accessibilityIdentifier("mockScanField")
                Button("このコードをスキャン") {
                    onScan(manualCode)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("mockScanSubmit")

                if let injected = ProcessInfo.processInfo.environment["uiTestScanCode"], !injected.isEmpty {
                    Button("注入コードをスキャン") { onScan(injected) }
                        .foregroundColor(.white)
                        .accessibilityIdentifier("mockScanInjected")
                }
            }
        }
    }
}
