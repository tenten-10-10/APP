import Foundation
import CoreGraphics
import CoreText
import UIKit

/// Generates the print-calibration A4 PDF (spec §7.7): the same code rendered at
/// several physical sizes and error-correction levels, a normal vs. shrunk
/// quiet-zone comparison, module dimensions, and a "read OK on this device"
/// checkbox per sample. Used to verify what a given printer + phone can read.
public struct CalibrationSheetRenderer {

    public let encoder: QREncoding

    public init(encoder: QREncoding = CoreImageQREncoder()) {
        self.encoder = encoder
    }

    private let sampleSizesMM: [Double] = [8, 10, 12, 16, 20, 28]
    private let eccLevels: [QRErrorCorrectionLevel] = [.low, .medium, .quartile]

    public func render(code: String) -> Data {
        let page = PaperSize.a4.sizePoints
        let margin = CGFloat(QRMeasurement.millimetersToPoints(12))

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return data as Data }
        var mediaBox = CGRect(origin: .zero, size: page)
        let info = [kCGPDFContextCreator as String: "ProjectStock"] as CFDictionary
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, info) else { return data as Data }

        ctx.beginPDFPage(nil)
        var cursorY = page.height - margin

        drawText("タナミル 印刷校正シート", at: CGPoint(x: margin, y: cursorY - 14),
                 size: 14, weight: .bold, context: ctx)
        cursorY -= 26
        drawText("コード: \(code)", at: CGPoint(x: margin, y: cursorY - 10), size: 9, context: ctx)
        cursorY -= 18
        drawText("各QRをこの端末でスキャンし、読み取れたらチェックしてください。プリンタ・用紙ごとに結果が変わります。",
                 at: CGPoint(x: margin, y: cursorY - 9), size: 8, color: UIColor.darkGray, context: ctx)
        cursorY -= 22

        // Size sweep at error-correction M.
        drawText("サイズ比較（誤り訂正 M）", at: CGPoint(x: margin, y: cursorY - 10), size: 10, weight: .semibold, context: ctx)
        cursorY -= 18
        if let mMatrix = try? encoder.encode(code, errorCorrection: .medium) {
            cursorY = drawSampleRow(sizes: sampleSizesMM, matrix: mMatrix, ecc: .medium,
                                    startY: cursorY, margin: margin, pageWidth: page.width, context: ctx)
        }
        cursorY -= 10

        // ECC comparison at a fixed 16 mm.
        drawText("誤り訂正レベル比較（16mm）", at: CGPoint(x: margin, y: cursorY - 10), size: 10, weight: .semibold, context: ctx)
        cursorY -= 18
        var matricesByECC: [(QRErrorCorrectionLevel, QRCodeMatrix)] = []
        for ecc in eccLevels {
            if let m = try? encoder.encode(code, errorCorrection: ecc) { matricesByECC.append((ecc, m)) }
        }
        cursorY = drawECCRow(items: matricesByECC, sizeMM: 16, startY: cursorY,
                             margin: margin, context: ctx)
        cursorY -= 10

        // Quiet-zone comparison: correct (4) vs. warning (1).
        drawText("Quiet Zone 比較（16mm）", at: CGPoint(x: margin, y: cursorY - 10), size: 10, weight: .semibold, context: ctx)
        cursorY -= 18
        if let m = try? encoder.encode(code, errorCorrection: .medium) {
            cursorY = drawQuietZoneComparison(matrix: m, sizeMM: 16, startY: cursorY, margin: margin, context: ctx)
        }

        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    // MARK: - Row drawers

    private func drawSampleRow(sizes: [Double], matrix: QRCodeMatrix, ecc: QRErrorCorrectionLevel,
                               startY: CGFloat, margin: CGFloat, pageWidth: CGFloat, context: CGContext) -> CGFloat {
        var x = margin
        let rowTop = startY
        let labelHeight: CGFloat = 26
        var maxLabelPts: CGFloat = 0
        for sizeMM in sizes {
            let sizePts = CGFloat(QRMeasurement.millimetersToPoints(sizeMM))
            maxLabelPts = max(maxLabelPts, sizePts)
            if x + sizePts > pageWidth - margin { break }
            let qrRect = CGRect(x: x, y: rowTop - sizePts, width: sizePts, height: sizePts)
            let spec = QRRenderSpec(code: "", totalSizeMM: sizeMM, errorCorrection: ecc)
            QRVectorPDFRenderer.draw(matrix: matrix, quietZoneModules: 4, in: qrRect,
                                     context: context, background: .whiteQuietZone)
            let moduleMM = sizeMM / Double(matrix.moduleCount + 8)
            drawText("\(Int(sizeMM))mm", at: CGPoint(x: x, y: rowTop - sizePts - 10), size: 7, context: context)
            drawText(String(format: "%.2fmm/mod", moduleMM),
                     at: CGPoint(x: x, y: rowTop - sizePts - 19), size: 6, color: .darkGray, context: context)
            drawCheckbox(at: CGPoint(x: x, y: rowTop - sizePts - 30), context: context)
            _ = spec
            x += sizePts + 12
        }
        return rowTop - maxLabelPts - labelHeight - 8
    }

    private func drawECCRow(items: [(QRErrorCorrectionLevel, QRCodeMatrix)], sizeMM: Double,
                            startY: CGFloat, margin: CGFloat, context: CGContext) -> CGFloat {
        var x = margin
        let sizePts = CGFloat(QRMeasurement.millimetersToPoints(sizeMM))
        for (ecc, matrix) in items {
            let qrRect = CGRect(x: x, y: startY - sizePts, width: sizePts, height: sizePts)
            QRVectorPDFRenderer.draw(matrix: matrix, quietZoneModules: 4, in: qrRect,
                                     context: context, background: .whiteQuietZone)
            drawText("ECC \(ecc.rawValue) · v\(matrix.version)",
                     at: CGPoint(x: x, y: startY - sizePts - 10), size: 7, context: context)
            drawCheckbox(at: CGPoint(x: x, y: startY - sizePts - 21), context: context)
            x += sizePts + 24
        }
        return startY - sizePts - 30
    }

    private func drawQuietZoneComparison(matrix: QRCodeMatrix, sizeMM: Double,
                                         startY: CGFloat, margin: CGFloat, context: CGContext) -> CGFloat {
        let sizePts = CGFloat(QRMeasurement.millimetersToPoints(sizeMM))
        // Correct quiet zone.
        let correctRect = CGRect(x: margin, y: startY - sizePts, width: sizePts, height: sizePts)
        QRVectorPDFRenderer.draw(matrix: matrix, quietZoneModules: 4, in: correctRect,
                                 context: context, background: .whiteQuietZone)
        drawText("正常 (4モジュール)", at: CGPoint(x: margin, y: startY - sizePts - 10), size: 7, context: context)
        drawCheckbox(at: CGPoint(x: margin, y: startY - sizePts - 21), context: context)

        // Warning: insufficient quiet zone.
        let warnX = margin + sizePts + 30
        let warnRect = CGRect(x: warnX, y: startY - sizePts, width: sizePts, height: sizePts)
        QRVectorPDFRenderer.draw(matrix: matrix, quietZoneModules: 1, in: warnRect,
                                 context: context, background: .whiteQuietZone)
        drawText("警告例 (1モジュール)", at: CGPoint(x: warnX, y: startY - sizePts - 10), size: 7,
                 color: UIColor.systemRed, context: context)
        drawCheckbox(at: CGPoint(x: warnX, y: startY - sizePts - 21), context: context)

        return startY - sizePts - 30
    }

    // MARK: - Primitives

    private func drawCheckbox(at point: CGPoint, context: CGContext) {
        let box = CGRect(x: point.x, y: point.y, width: 9, height: 9)
        context.saveGState()
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(0.5)
        context.stroke(box)
        context.restoreGState()
        drawText("読取OK", at: CGPoint(x: point.x + 12, y: point.y), size: 6, color: .darkGray, context: context)
    }

    private func drawText(_ text: String, at point: CGPoint, size: CGFloat,
                          weight: UIFont.Weight = .regular, color: UIColor = .black, context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.saveGState()
        context.textPosition = point
        context.textMatrix = .identity
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
