import Foundation
import CoreImage

/// Abstraction over QR encoding so a Micro QR / rMQR encoder can be substituted
/// later without touching the renderers (spec §6).
public protocol QREncoding {
    func encode(_ message: String, errorCorrection: QRErrorCorrectionLevel) throws -> QRCodeMatrix
}

public enum QREncoderError: LocalizedError {
    case filterUnavailable
    case renderFailed
    case emptyMatrix
    case malformedMatrix

    public var errorDescription: String? {
        switch self {
        case .filterUnavailable: return NSLocalizedString("QR生成フィルタを初期化できませんでした。", comment: "")
        case .renderFailed:      return NSLocalizedString("QR画像の生成に失敗しました。", comment: "")
        case .emptyMatrix:       return NSLocalizedString("QRモジュールを読み取れませんでした。", comment: "")
        case .malformedMatrix:   return NSLocalizedString("生成されたQRが正方形ではありません。", comment: "")
        }
    }
}

/// Standard-QR encoder built on `CIQRCodeGenerator`. It renders the symbol at
/// native 1-module-per-pixel resolution, samples every pixel, and trims the
/// generator's built-in quiet zone to recover the bare data region as a
/// `QRCodeMatrix`. We own quiet-zone insertion afterwards.
public final class CoreImageQREncoder: QREncoding {

    private let ciContext: CIContext

    public init() {
        // Software renderer keeps output deterministic and avoids GPU color
        // management surprises for the 1px-per-module read-back.
        self.ciContext = CIContext(options: [.useSoftwareRenderer: true])
    }

    public func encode(_ message: String, errorCorrection: QRErrorCorrectionLevel) throws -> QRCodeMatrix {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw QREncoderError.filterUnavailable
        }
        let data = Data(message.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(errorCorrection.rawValue, forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage else { throw QREncoderError.renderFailed }
        // Output extent is integral with 1 pixel == 1 module (+ built-in border).
        let extent = output.extent
        guard let cgImage = ciContext.createCGImage(output, from: extent) else {
            throw QREncoderError.renderFailed
        }

        let grid = try Self.sampleGrid(from: cgImage)
        let trimmed = Self.trimQuietZone(grid)
        let count = trimmed.count
        guard count >= 21 else { throw QREncoderError.emptyMatrix }
        let matrix = QRCodeMatrix(moduleCount: count, modules: trimmed)
        guard matrix.isWellFormed else { throw QREncoderError.malformedMatrix }
        return matrix
    }

    // MARK: - Pixel sampling

    /// Render a CGImage into a known RGBA8 buffer and threshold to a Bool grid
    /// (`true` == dark). `createCGImage` already returns top-left origin.
    private static func sampleGrid(from cgImage: CGImage) throws -> [[Bool]] {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { throw QREncoderError.emptyMatrix }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        // The CGContext must only use the buffer pointer while it is valid, so
        // keep the draw inside `withUnsafeMutableBytes`.
        var drew = false
        buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                          space: colorSpace, bitmapInfo: bitmapInfo) else { return }
            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            drew = true
        }
        guard drew else { throw QREncoderError.renderFailed }

        var grid = [[Bool]](repeating: [Bool](repeating: false, count: width), count: height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Int(buffer[offset])
                let g = Int(buffer[offset + 1])
                let b = Int(buffer[offset + 2])
                let luminance = (r * 299 + g * 587 + b * 114) / 1000
                grid[y][x] = luminance < 128       // dark module
            }
        }
        return grid
    }

    /// Trim the uniform light border (quiet zone) around the data region.
    private static func trimQuietZone(_ grid: [[Bool]]) -> [[Bool]] {
        let height = grid.count
        guard height > 0 else { return grid }
        let width = grid[0].count

        var minRow = height, maxRow = -1, minCol = width, maxCol = -1
        for y in 0..<height {
            for x in 0..<width where grid[y][x] {
                if y < minRow { minRow = y }
                if y > maxRow { maxRow = y }
                if x < minCol { minCol = x }
                if x > maxCol { maxCol = x }
            }
        }
        guard maxRow >= minRow, maxCol >= minCol else { return grid }

        var trimmed: [[Bool]] = []
        trimmed.reserveCapacity(maxRow - minRow + 1)
        for y in minRow...maxRow {
            trimmed.append(Array(grid[y][minCol...maxCol]))
        }
        return trimmed
    }
}
