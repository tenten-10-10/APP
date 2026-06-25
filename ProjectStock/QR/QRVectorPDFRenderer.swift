import Foundation
import CoreGraphics
import CoreText
import UIKit

/// Generates true vector PDFs (spec §7.5). QR modules are drawn as filled
/// rectangle paths in PostScript points — never a rasterized image. Horizontal
/// runs are merged to keep the file small.
public struct QRVectorPDFRenderer {

    public init() {}

    public enum PDFError: LocalizedError {
        case consumerFailed
        case contextFailed
        public var errorDescription: String? {
            switch self {
            case .consumerFailed: return "PDFデータの作成に失敗しました。"
            case .contextFailed:  return "PDF描画コンテキストを作成できませんでした。"
            }
        }
    }

    /// A single label sized exactly to the requested physical dimensions,
    /// optionally with a caption (name / SKU) drawn beneath the code.
    public func renderSingleLabel(matrix: QRCodeMatrix, spec: QRRenderSpec,
                                  caption: String? = nil) throws -> Data {
        let sizePts = CGFloat(QRMeasurement.millimetersToPoints(spec.totalSizeMM))
        let captionHeight: CGFloat = caption == nil ? 0 : 14
        let pageWidth = sizePts
        let pageHeight = sizePts + captionHeight

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { throw PDFError.consumerFailed }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let pdfInfo = [kCGPDFContextCreator as String: "ProjectStock"] as CFDictionary
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, pdfInfo) else {
            throw PDFError.contextFailed
        }

        context.beginPDFPage(nil)
        let qrRect = CGRect(x: 0, y: captionHeight, width: sizePts, height: sizePts)
        Self.draw(matrix: matrix, quietZoneModules: spec.quietZoneModules,
                  in: qrRect, context: context, background: spec.background)
        if let caption {
            Self.drawCaption(caption, in: CGRect(x: 0, y: 0, width: pageWidth, height: captionHeight),
                             context: context)
        }
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    // MARK: - Reusable vector drawing

    /// Draw a padded QR symbol into `rect` of an existing CG context using
    /// vector rectangles. Shared by the single-label and sheet renderers.
    static func draw(matrix: QRCodeMatrix, quietZoneModules: Int, in rect: CGRect,
                     context: CGContext, background: QRBackgroundMode) {
        let padded = matrix.paddedGrid(quietZoneModules: quietZoneModules)
        let total = CGFloat(padded.totalModuleCount)
        let module = min(rect.width, rect.height) / total
        let originX = rect.minX
        let originY = rect.minY

        // Background fill for the label area (quiet zone stays white by default).
        switch background {
        case .whiteQuietZone, .solidWhite:
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: originX, y: originY, width: module * total, height: module * total))
        case .fullyTransparent:
            break // leave the page/background showing through
        }

        context.setFillColor(UIColor.black.cgColor)
        let count = padded.totalModuleCount
        for row in 0..<count {
            // PDF origin is bottom-left; row 0 is the visual top.
            let y = originY + CGFloat(count - 1 - row) * module
            for run in padded.darkRuns(inRow: row) {
                let x = originX + CGFloat(run.start) * module
                let runRect = CGRect(x: x, y: y, width: CGFloat(run.length) * module, height: module)
                context.fill(runRect)
            }
        }
    }

    static func drawCaption(_ text: String, in rect: CGRect, context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7, weight: .regular),
            .foregroundColor: UIColor.black
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let x = rect.midX - bounds.width / 2
        let y = rect.midY - bounds.height / 2
        context.saveGState()
        context.textPosition = CGPoint(x: max(rect.minX + 1, x), y: max(rect.minY + 1, y))
        context.textMatrix = .identity
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
