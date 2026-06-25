import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

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

    public func renderPNG(matrix: QRCodeMatrix, spec: QRRenderSpec) throws -> QRRasterResult {
        let padded = matrix.paddedGrid(quietZoneModules: spec.quietZoneModules)
        let geometry = QRPixelGeometry.resolve(totalModuleCount: padded.totalModuleCount,
                                               requestedSizeMM: spec.totalSizeMM,
                                               dpi: spec.dpi)
        let image = try makeImage(padded: padded, geometry: geometry, background: spec.background)
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
                           background: QRBackgroundMode) throws -> CGImage {
        let dim = geometry.pixelDimension
        let module = geometry.modulePixelSize
        let bytesPerRow = dim * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()      // sRGB device RGB
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(data: nil, width: dim, height: dim,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: colorSpace, bitmapInfo: bitmapInfo) else {
            throw RasterError.contextFailed
        }
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.setAllowsAntialiasing(false)

        // Background.
        switch background {
        case .whiteQuietZone, .solidWhite:
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: dim, height: dim))
        case .fullyTransparent:
            context.clear(CGRect(x: 0, y: 0, width: dim, height: dim))
        }

        // Dark modules. CGContext origin is bottom-left, so flip rows.
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        let total = padded.totalModuleCount
        for row in 0..<total {
            let runs = padded.darkRuns(inRow: row)
            let y = (total - 1 - row) * module
            for run in runs {
                let rect = CGRect(x: run.start * module, y: y,
                                  width: run.length * module, height: module)
                context.fill(rect)
            }
        }

        guard let image = context.makeImage() else { throw RasterError.imageFailed }
        return image
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
