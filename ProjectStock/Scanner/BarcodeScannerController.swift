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
    private let debounceInterval: TimeInterval = 2.0
    /// When true, the same code can re-fire after the debounce window
    /// (continuous stocktake mode); when false the same code fires once.
    var allowsRepeatAfterDebounce: Bool = true

    private var isConfigured = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSessionIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        start()
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
        guard !isConfigured else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

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
        // Only request types the output actually supports to avoid a crash.
        let available = metadataOutput.availableMetadataObjectTypes
        return desired.filter { available.contains($0) }
    }

    private func installPreviewLayer() {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }

    // MARK: - Control

    func start() {
        guard isConfigured else { configureSessionIfNeeded(); sessionQueue.async { [weak self] in self?.startRunning() }; return }
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
