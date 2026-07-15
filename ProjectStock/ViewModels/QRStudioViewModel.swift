import SwiftUI
import UIKit
import Combine

/// Drives the QR Label Studio (spec §12.5): owns the render spec, re-encodes on
/// change, and produces the preview image + scanability report. Export is done
/// through `QRExportService` into the shared temp directory.
final class QRStudioViewModel: ObservableObject {

    let code: String
    let exportService = QRExportService()

    @Published var sizePreset: QRSizePreset
    @Published var customMM: Double = 20
    @Published var errorCorrection: QRErrorCorrectionLevel
    @Published var dpi: Int
    @Published var background: QRBackgroundMode = .whiteQuietZone
    @Published var format: QRExportFormat = .png
    @Published var showCaption: Bool = true

    @Published private(set) var previewImage: UIImage?
    @Published private(set) var report: QRScanabilityEvaluator.Report?
    @Published private(set) var encodeError: String?

    private var matrix: QRCodeMatrix?
    private var cancellables = Set<AnyCancellable>()

    init(code: String, settings: AppSettings) {
        self.code = code
        self.sizePreset = settings.defaultSizePreset
        self.errorCorrection = settings.defaultErrorCorrection
        self.dpi = settings.defaultDPI

        // Re-render whenever any visual input changes.
        Publishers.MergeMany(
            $sizePreset.map { _ in () }.eraseToAnyPublisher(),
            $customMM.map { _ in () }.eraseToAnyPublisher(),
            $errorCorrection.map { _ in () }.eraseToAnyPublisher(),
            $dpi.map { _ in () }.eraseToAnyPublisher(),
            $background.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
        .sink { [weak self] _ in self?.rebuild() }
        .store(in: &cancellables)

        rebuild()
    }

    var totalSizeMM: Double {
        sizePreset == .custom ? customMM : sizePreset.defaultMillimeters
    }

    var spec: QRRenderSpec {
        QRRenderSpec(code: code, totalSizeMM: totalSizeMM, errorCorrection: errorCorrection,
                     dpi: dpi, quietZoneModules: 4, background: background)
    }

    func rebuild() {
        do {
            let matrix = try exportService.encodeMatrix(code: code, errorCorrection: errorCorrection)
            self.matrix = matrix
            self.encodeError = nil
            self.previewImage = exportService.previewImage(matrix: matrix, spec: spec)
            self.report = exportService.evaluate(matrix: matrix, spec: spec)
        } catch {
            self.encodeError = error.localizedDescription
            self.previewImage = nil
            self.report = nil
        }
    }

    /// Export the current spec in the chosen format; returns a temp file URL.
    /// Includes the code itself below the QR (unless `showCaption` is off) so
    /// a printed label is still identifiable by eye, e.g. if a scan fails.
    func export(projectName: String, targetName: String) throws -> URL {
        let context = QRExportService.ExportContext(projectName: projectName, targetName: targetName)
        return try exportService.exportFile(spec: spec, format: format, context: context,
                                            caption: showCaption ? code : nil)
    }

    func exportCalibrationSheet(projectName: String, targetName: String) throws -> URL {
        let context = QRExportService.ExportContext(projectName: projectName, targetName: targetName)
        return try exportService.exportCalibrationSheet(code: code, context: context)
    }
}
