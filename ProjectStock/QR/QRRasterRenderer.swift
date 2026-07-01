import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import UIKit

/// Pixel geometry resolved for a raster export. Integer module size guarantees
/// every module is crisp; the actual physical size may differ slightly from the
/// requested size and that difference is surfaced to the user (spec §7.4).
public struct QRPixelGeometry {
    public let totalModuleCount: Int
    public let modulePixelSize: Int
    public let pixelDimension: Int
    public let requestedSizeMM: Double
    public let dpi: Int

    public var actualSizeMM: Double {
        QRMeasurement.pixelsToMillimeters(Double(pixelDimension), dpi: dpi)
    }
    public var sizeDifferenceMM: Double { actualSizeMM - requestedSizeMM }
    public var modulePhysicalMM: Double {
        QRMeasurement.pixelsToMillimeters(Double(modulePixelSize), dpi: dpi)
    }

    static func resolve(totalModuleCount: Int, requestedSizeMM: Double, dpi: Int) -> QRPixelGeometry {
        let targetPixels = QRMeasurement.millimetersToPixels(requestedSizeMM, dpi: dpi)
        let modulePx = max(1, Int((targetPixels / Double(totalModuleCount)).rounded()))
        let dimension = modulePx * totalModuleCount
        return QRPixelGeometry(totalModuleCount: totalModuleCount,
                               modulePixelSize: modulePx,
                               pixelDimension: dimension,
                               requestedSizeMM: requestedSizeMM,
                               dpi: dpi)
    }
}

public struct QRRasterResult {
    public let pngData: Data
    public let geometry: QRPixelGeometry
    public let cgImage: CGImage
}

/// Renders a `QRCodeMatrix` to a transparent / opaque PNG with NO antialiasing,
/// NO interpolation and integer module pixels (spec §7.4).
public struct QRRasterRenderer {

    public init() {}

    public enum RasterError: LocalizedError {
        case contextFailed
        case imageFailed
        case encodeFailed
        public var errorDescription: String? {
            switch self {
            case .contextFailed: return "描画コンテキストを作成できませんでした。"
            case .imageFailed:   return "画像を生成できませんでした。"
            case .encodeFailed:  return "PNGへの書き出しに失敗しました。"
            }
        }
    }

    /// - Parameter caption: When non-nil, the code is printed as a small
    ///   human-readable strip below the QR (e.g. the public code itself), so a
    ///   printed label stays identifiable by eye if the QR can't be scanned.
    public func renderPNG(matrix: QRCodeMatrix, spec: QRRenderSpec, caption: String? = nil) throws -> QRRasterResult {
        let padded = matrix.paddedGrid(quietZoneModules: spec.quietZoneModules)
        let geometry = QRPixelGeometry.resolve(totalModuleCount: padded.totalModuleCount,
                                               requestedSizeMM: spec.totalSizeMM,
                                               dpi: spec.dpi)
        let image = try makeImage(padded: padded, geometry: geometry, background: spec.background,
                                  caption: caption, dpi: spec.dpi)
        let data = try encodePNG(image, dpi: spec.dpi)
        return QRRasterResult(pngData: data, geometry: geometry, cgImage: image)
    }

    /// A crisp on-screen preview image at a fixed module pixel size (decoupled
    /// from physical size so an 8 mm label still previews large).
    public func previewImage(matrix: QRCodeMatrix, quietZoneModules: Int = 4,
                             targetDimension: Int = 720,
                             background: QRBackgroundMode = .whiteQuietZone) -> CGImage? {
        let padded = matrix.paddedGrid(quietZoneModules: quietZoneModules)
        let modulePx = max(1, targetDimension / padded.totalModuleCount)
        let geometry = QRPixelGeometry(totalModuleCount: padded.totalModuleCount,
                                       modulePixelSize: modulePx,
                                       pixelDimension: modulePx * padded.totalModuleCount,
                                       requestedSizeMM: 0, dpi: 72)
        return try? makeImage(padded: padded, geometry: geometry, background: background)
    }

    // MARK: - Drawing

    private func makeImage(padded: PaddedQRGrid, geometry: QRPixelGeometry,
                           background: QRBackgroundMode, caption: String? = nil,
                           dpi: Int = 72) throws -> CGImage {
        let dim = geometry.pixelDimension
        let module = geometry.modulePixelSize
        // A caption band below the QR, sized to a fixed physical height so it
        // stays legible whatever the label's print size / dpi.
        let captionHeightPx = caption != nil
            ? Int(QRMeasurement.millimetersToPixels(3.0, dpi: dpi).rounded())
            : 0
        let width = dim
        let height = dim + captionHeightPx
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()      // sRGB device RGB
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: colorSpace, bitmapInfo: bitmapInfo) else {
            throw RasterError.contextFailed
        }
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.setAllowsAntialiasing(false)

        // Background for the QR's own quiet zone.
        switch background {
        case .whiteQuietZone, .solidWhite:
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: CGFloat(captionHeightPx), width: CGFloat(dim), height: CGFloat(dim)))
        case .fullyTransparent:
            context.clear(CGRect(x: 0, y: CGFloat(captionHeightPx), width: CGFloat(dim), height: CGFloat(dim)))
        }

        // The caption band always gets a plain white backdrop, independent of
        // the QR's own background mode, so the human-readable code stays
        // legible even when the QR itself uses a transparent quiet zone.
        if captionHeightPx > 0 {
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(captionHeightPx)))
        }

        // Dark modules. CGContext origin is bottom-left, so flip rows; shift up
        // to leave room for the caption band beneath.
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        let total = padded.totalModuleCount
        for row in 0..<total {
            let runs = padded.darkRuns(inRow: row)
            let y = captionHeightPx + (total - 1 - row) * module
            for run in runs {
                let rect = CGRect(x: run.start * module, y: y,
                                  width: run.length * module, height: module)
                context.fill(rect)
            }
        }

        if let caption, captionHeightPx > 0 {
            Self.drawFittedCaption(caption, boxWidth: width, boxHeight: captionHeightPx, dpi: dpi, context: context)
        }

        guard let image = context.makeImage() else { throw RasterError.imageFailed }
        return image
    }

    /// Draw `text` centered in a `boxWidth`×`boxHeight` band at the bottom of
    /// the image, shrinking the font until it fits so long codes never clip on
    /// small physical labels.
    static func drawFittedCaption(_ text: String, boxWidth: Int, boxHeight: Int, dpi: Int, context: CGContext) {
        let maxWidth = CGFloat(boxWidth) * 0.92
        let minFontSize = CGFloat(QRMeasurement.millimetersToPixels(0.9, dpi: dpi))
        var fontSize = CGFloat(QRMeasurement.millimetersToPixels(1.8, dpi: dpi))

        func makeLine(_ size: CGFloat) -> (CTLine, CGRect) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: size, weight: .regular),
                .foregroundColor: UIColor.black
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            return (line, CTLineGetBoundsWithOptions(line, .useOpticalBounds))
        }

        var (line, bounds) = makeLine(fontSize)
        while bounds.width > maxWidth && fontSize > minFontSize {
            fontSize -= max(1, fontSize * 0.1)
            (line, bounds) = makeLine(fontSize)
        }

        let x = (CGFloat(boxWidth) - bounds.width) / 2 - bounds.minX
        let y = (CGFloat(boxHeight) - bounds.height) / 2 - bounds.minY
        context.saveGState()
        context.textPosition = CGPoint(x: x, y: y)
        context.textMatrix = .identity
        CTLineDraw(line, context)
        context.restoreGState()
    }

    // MARK: - Encoding

    private func encodePNG(_ image: CGImage, dpi: Int) throws -> Data {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData, UTType.png.identifier as CFString, 1, nil) else {
            throw RasterError.encodeFailed
        }
        // Embed DPI so the printed size is honored by print pipelines.
        let dpiValue = Double(dpi)
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpiValue,
            kCGImagePropertyDPIHeight: dpiValue,
            kCGImagePropertyHasAlpha: true
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw RasterError.encodeFailed }
        return mutableData as Data
    }
}
