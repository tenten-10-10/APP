import Foundation
import CoreGraphics
import UIKit

/// Orchestrates QR encoding, evaluation and file export. It keeps the separate
/// renderers behind one façade and writes share-able files to a managed
/// temporary directory that can be purged (spec §16).
public final class QRExportService {

    private let encoder: QREncoding
    private let raster = QRRasterRenderer()
    private let pdf = QRVectorPDFRenderer()
    private let eps = QREPSRenderer()
    private let svg = QRSVGRenderer()
    private let sheet = LabelSheetRenderer()
    private let evaluator = QRScanabilityEvaluator()
    private lazy var calibration = CalibrationSheetRenderer(encoder: encoder)

    public init(encoder: QREncoding = CoreImageQREncoder()) {
        self.encoder = encoder
    }

    /// Filename context (spec §7.4/§7.6 naming).
    public struct ExportContext {
        public var projectName: String
        public var targetName: String
        public init(projectName: String, targetName: String) {
            self.projectName = projectName
            self.targetName = targetName
        }
    }

    // MARK: - Encoding / evaluation

    public func encodeMatrix(code: String, errorCorrection: QRErrorCorrectionLevel) throws -> QRCodeMatrix {
        // Encode the Universal Link URL (not the bare code) so the label opens
        // タナミル when installed, or the App Store when not — even when scanned
        // by the plain iPhone Camera app. The scanner extracts the code back out.
        try encoder.encode(AppConfig.qrPayload(for: code), errorCorrection: errorCorrection)
    }

    public func evaluate(matrix: QRCodeMatrix, spec: QRRenderSpec) -> QRScanabilityEvaluator.Report {
        evaluator.evaluate(matrix: matrix, spec: spec)
    }

    public func previewImage(matrix: QRCodeMatrix, spec: QRRenderSpec) -> UIImage? {
        guard let cg = raster.previewImage(matrix: matrix, quietZoneModules: spec.quietZoneModules,
                                           background: spec.background) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - Single-label file export

    public func exportFile(spec: QRRenderSpec, format: QRExportFormat,
                           context: ExportContext) throws -> URL {
        let matrix = try encodeMatrix(code: spec.code, errorCorrection: spec.errorCorrection)
        let data: Data
        switch format {
        case .png:
            data = try raster.renderPNG(matrix: matrix, spec: spec).pngData
        case .pdf:
            data = try pdf.renderSingleLabel(matrix: matrix, spec: spec,
                                             caption: nil)
        case .eps:
            data = eps.renderEPS(matrix: matrix, spec: spec, title: context.targetName)
        case .svg:
            data = svg.renderSVG(matrix: matrix, spec: spec)
        }
        let name = filename(context: context, code: spec.code, sizeMM: spec.totalSizeMM,
                            ext: format.fileExtension)
        return try write(data: data, filename: name)
    }

    // MARK: - Sheets

    public func exportLabelSheet(codes: [(code: String, caption: String?)],
                                 options: LabelSheetOptions,
                                 context: ExportContext) throws -> URL {
        let items: [LabelSheetItem] = try codes.map { entry in
            let matrix = try encodeMatrix(code: entry.code,
                                          errorCorrection: options.background == .fullyTransparent ? .medium : .medium)
            return LabelSheetItem(matrix: matrix, code: entry.code, caption: entry.caption)
        }
        let data = sheet.render(items: items, options: options)
        let name = sanitize(context.projectName) + "_labels_\(Int(options.labelSizeMM))mm.pdf"
        return try write(data: data, filename: name)
    }

    public func exportCalibrationSheet(code: String, context: ExportContext) throws -> URL {
        let data = calibration.render(code: code)
        let name = sanitize(context.projectName) + "_calibration.pdf"
        return try write(data: data, filename: name)
    }

    // MARK: - Filenames & temp storage (spec §16: temp dir, purgeable)

    /// `{project}_{target}_{code}_{size}mm.ext`
    func filename(context: ExportContext, code: String, sizeMM: Double, ext: String) -> String {
        let size = sizeMM == sizeMM.rounded() ? String(Int(sizeMM)) : String(format: "%.1f", sizeMM)
        return "\(sanitize(context.projectName))_\(sanitize(context.targetName))_\(code)_\(size)mm.\(ext)"
    }

    private func sanitize(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(mapped).replacingOccurrences(of: "--", with: "-")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "label" : String(trimmed.prefix(40))
    }

    /// Directory under the temporary directory used for all generated exports.
    public static let exportDirectoryName = "QRExports"

    public func exportDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Self.exportDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(data: Data, filename: String) throws -> URL {
        let url = try exportDirectory().appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Remove generated files older than `maxAge` (called on launch / after share).
    public func purgeOldExports(olderThan maxAge: TimeInterval = 3600) {
        guard let dir = try? exportDirectory() else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for file in files {
            if let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               date < cutoff {
                try? fm.removeItem(at: file)
            }
        }
    }
}
