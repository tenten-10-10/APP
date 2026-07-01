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

    /// Fixed vertical space reserved below every QR for its labels + checkbox,
    /// measured down from that QR's own bottom edge.
    private let labelBlockHeight: CGFloat = 36

    /// Draws one QR + its label lines + checkbox as a self-contained unit whose
    /// bottom (checkbox) sits `labelBlockHeight` below the QR's bottom edge —
    /// used by every row so labels/checkboxes never drift relative to the code
    /// they describe.
    private func drawSample(matrix: QRCodeMatrix, sizePts: CGFloat, at x: CGFloat, bottomY: CGFloat,
                            lines: [(text: String, size: CGFloat, color: UIColor)],
                            context: CGContext) {
        let qrRect = CGRect(x: x, y: bottomY, width: sizePts, height: sizePts)
        QRVectorPDFRenderer.draw(matrix: matrix, quietZoneModules: 4, in: qrRect,
                                 context: context, background: .whiteQuietZone)
        var lineY = bottomY - 10
        for line in lines {
            drawText(line.text, at: CGPoint(x: x, y: lineY), size: line.size, color: line.color, context: context)
            lineY -= 9
        }
        drawCheckbox(at: CGPoint(x: x, y: lineY - 2), context: context)
    }

    /// A row of the SAME code at different physical sizes, all sharing one
    /// bottom edge so every size's label + checkbox lines up on one common
    /// line beneath the row (rather than trailing off under each code).
    private func drawSampleRow(sizes: [Double], matrix: QRCodeMatrix, ecc: QRErrorCorrectionLevel,
                               startY: CGFloat, margin: CGFloat, pageWidth: CGFloat, context: CGContext) -> CGFloat {
        let sizePtsList = sizes.map { CGFloat(QRMeasurement.millimetersToPoints($0)) }
        let maxSizePts = sizePtsList.max() ?? 0
        let rowBottom = startY - maxSizePts
        var x = margin
        for (sizeMM, sizePts) in zip(sizes, sizePtsList) {
            if x + sizePts > pageWidth - margin { break }
            let moduleMM = sizeMM / Double(matrix.moduleCount + 8)
            drawSample(matrix: matrix, sizePts: sizePts, at: x, bottomY: rowBottom, lines: [
                ("\(Int(sizeMM))mm", 7, .black),
                (String(format: "%.2fmm/mod", moduleMM), 6, .darkGray)
            ], context: context)
            x += sizePts + 14
        }
        return rowBottom - labelBlockHeight - 12
    }

    private func drawECCRow(items: [(QRErrorCorrectionLevel, QRCodeMatrix)], sizeMM: Double,
                            startY: CGFloat, margin: CGFloat, context: CGContext) -> CGFloat {
        let sizePts = CGFloat(QRMeasurement.millimetersToPoints(sizeMM))
        let rowBottom = startY - sizePts
        var x = margin
        for (ecc, matrix) in items {
            drawSample(matrix: matrix, sizePts: sizePts, at: x, bottomY: rowBottom, lines: [
                ("ECC \(ecc.rawValue) · v\(matrix.version)", 7, .black)
            ], context: context)
            x += sizePts + 26
        }
        return rowBottom - labelBlockHeight - 12
    }

    private func drawQuietZoneComparison(matrix: QRCodeMatrix, sizeMM: Double,
                                         startY: CGFloat, margin: CGFloat, context: CGContext) -> CGFloat {
        let sizePts = CGFloat(QRMeasurement.millimetersToPoints(sizeMM))
        let rowBottom = startY - sizePts

        drawSample(matrix: matrix, sizePts: sizePts, at: margin, bottomY: rowBottom, lines: [
            ("正常 (4モジュール)", 7, .black)
        ], context: context)
        // Redraw with a shrunk quiet zone for the warning example (drawSample
        // always uses 4 modules, so this one bypasses it to use 1).
        let warnX = margin + sizePts + 30
        let warnRect = CGRect(x: warnX, y: rowBottom, width: sizePts, height: sizePts)
        QRVectorPDFRenderer.draw(matrix: matrix, quietZoneModules: 1, in: warnRect,
                                 context: context, background: .whiteQuietZone)
        drawText("警告例 (1モジュール)", at: CGPoint(x: warnX, y: rowBottom - 10), size: 7,
                 color: UIColor.systemRed, context: context)
        drawCheckbox(at: CGPoint(x: warnX, y: rowBottom - 21), context: context)

        return rowBottom - labelBlockHeight - 12
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
