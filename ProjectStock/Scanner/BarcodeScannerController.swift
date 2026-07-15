import UIKit
import AVFoundation

/// AVFoundation QR scanner (spec §8). Uses `AVCaptureSession` +
/// `AVCaptureMetadataOutput` rather than VisionKit so iOS 15 / iPhone SE (1st
/// gen) are supported. Micro QR is added only when the OS exposes it.
final class BarcodeScannerController: UIViewController {

    /// Called on the main thread for each accepted (debounced) scan.
    var onScan: ((String) -> Void)?
    /// Called when the session cannot start (no camera, config failure).
    var onSessionError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let metadataOutput = AVCaptureMetadataOutput()
    private let sessionQueue = DispatchQueue(label: "ProjectStock.scanner.session")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var captureDevice: AVCaptureDevice?

    // Duplicate suppression (spec §8: 同一コードの連続発火防止).
    private var lastAcceptedCode: String?
    private var lastAcceptedAt: Date = .distantPast
    /// Seconds before the SAME code may fire again in continuous mode. ハンディ
    /// uses a shorter window (rapid deliberate re-scans of one shelf item).
    var debounceInterval: TimeInterval = 2.0
    /// When true, the same code can re-fire after the debounce window
    /// (continuous stocktake mode); when false the same code fires once.
    var allowsRepeatAfterDebounce: Bool = true
    /// When true, also detect 1D retail/logistics barcodes (JAN/EAN, UPC-A,
    /// ITF-14). Off for the normal QR tab so its behavior is unchanged; the
    /// ハンディモード scanner opts in. Must be set before the view loads.
    var detectsOneDimensional: Bool = false

    private var isConfigured = false
    /// Set synchronously on the main thread the first time configuration is
    /// requested, so `start()` can't enqueue a second configuration pass (which
    /// previously added a duplicate preview layer and slowed the first frame).
    private var didRequestConfigure = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSessionIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        resetDebounce() // returning to the screen must allow re-scanning the same code
        if !pausedByUI { start() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    // MARK: - Session configuration

    private func configureSessionIfNeeded() {
        guard !didRequestConfigure else { return }
        didRequestConfigure = true
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            // A 720p preset starts noticeably faster than the default high/photo
            // preset and is more than enough resolution for QR detection.
            if self.session.canSetSessionPreset(.hd1280x720) {
                self.session.sessionPreset = .hd1280x720
            }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(for: .video) else {
                DispatchQueue.main.async { self.onSessionError?(AppError.cameraUnavailable.localizedDescription) }
                return
            }
            self.captureDevice = device

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) { self.session.addInput(input) }
            } catch {
                DispatchQueue.main.async { self.onSessionError?(error.localizedDescription) }
                return
            }

            if self.session.canAddOutput(self.metadataOutput) {
                self.session.addOutput(self.metadataOutput)
                self.metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
                self.metadataOutput.metadataObjectTypes = self.supportedTypes()
            }
            self.isConfigured = true

            DispatchQueue.main.async { self.installPreviewLayer() }
        }
    }

    private func supportedTypes() -> [AVMetadataObject.ObjectType] {
        var desired: [AVMetadataObject.ObjectType] = [.qr]
        if #available(iOS 15.4, *) {
            desired.append(.microQR)
        }
        if detectsOneDimensional {
            // JAN = EAN-13/EAN-8; UPC-A arrives as .ean13 with a leading zero;
            // ITF-14 has its own type, plus .interleaved2of5 for printers that
            // encode the 14 digits as plain ITF.
            desired.append(contentsOf: [.ean13, .ean8, .itf14, .interleaved2of5])
        }
        // Only request types the output actually supports to avoid a crash.
        let available = metadataOutput.availableMetadataObjectTypes
        return desired.filter { available.contains($0) }
    }

    private func installPreviewLayer() {
        guard previewLayer == nil else { return }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }

    // MARK: - Control

    func start() {
        // Configuration is requested at most once; the serial sessionQueue
        // guarantees this startRunning runs after it completes.
        configureSessionIfNeeded()
        sessionQueue.async { [weak self] in self?.startRunning() }
    }

    private func startRunning() {
        if !session.isRunning { session.startRunning() }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    /// While a scan result is being shown, the camera must neither keep
    /// scanning nor deliver frames already in flight — otherwise a second QR
    /// entering the view replaces the result the user is looking at.
    private var pausedByUI = false

    func setPaused(_ paused: Bool) {
        guard paused != pausedByUI else { return }
        pausedByUI = paused
        if paused {
            stop()
        } else {
            // Re-arm the duplicate suppressor on resume: "fire once" means once
            // per presentation, not once per session. Without this, closing the
            // result sheet left the SAME QR permanently unscannable until a
            // different code was read first.
            resetDebounce()
            start()
        }
    }

    func resetDebounce() {
        lastAcceptedCode = nil
        lastAcceptedAt = .distantPast
    }

    // MARK: - Torch & zoom (spec §8)

    var supportsTorch: Bool { captureDevice?.hasTorch ?? false }

    func setTorch(on: Bool) {
        guard let device = captureDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch { /* non-fatal */ }
    }

    var maxZoomFactor: CGFloat {
        guard let device = captureDevice else { return 1 }
        return min(device.activeFormat.videoMaxZoomFactor, 8)
    }

    func setZoom(factor: CGFloat) {
        guard let device = captureDevice else { return }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = max(1, min(factor, maxZoomFactor))
            device.unlockForConfiguration()
        } catch { /* non-fatal */ }
    }
}

extension BarcodeScannerController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        // stopRunning() is async on the session queue; frames already in
        // flight still arrive here (delegate + setPaused both run on main).
        guard !pausedByUI else { return }
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue, !value.isEmpty else { return }

        let now = Date()
        if value == lastAcceptedCode {
            if !allowsRepeatAfterDebounce { return }
            if now.timeIntervalSince(lastAcceptedAt) < debounceInterval { return }
        }
        lastAcceptedCode = value
        lastAcceptedAt = now
        onScan?(value)
    }
}
