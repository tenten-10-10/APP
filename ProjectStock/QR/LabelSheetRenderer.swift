import Foundation
import CoreGraphics
import UIKit

public enum PaperSize {
    case a4
    case letter

    /// Page size in PostScript points.
    var sizePoints: CGSize {
        switch self {
        case .a4:     return CGSize(width: 595.28, height: 841.89) // 210×297 mm
        case .letter: return CGSize(width: 612, height: 792)       // 8.5×11 in
        }
    }

    var localizedTitle: String {
        switch self {
        case .a4: return "A4"
        case .letter: return "Letter"
        }
    }
}

/// One label to place on a sheet.
public struct LabelSheetItem {
    public let matrix: QRCodeMatrix
    public let code: String
    public let caption: String?
    public init(matrix: QRCodeMatrix, code: String, caption: String?) {
        self.matrix = matrix
        self.code = code
        self.caption = caption
    }
}

public struct LabelSheetOptions {
    public var labelSizeMM: Double = 16
    public var paper: PaperSize = .a4
    public var marginMM: Double = 10
    public var spacingMM: Double = 4
    /// Full rectangle border around each label.
    public var showCutGuides: Bool = false
    /// Printer-style corner crop marks (トンボ) just outside each label, for
    /// trimming or aligning to a die-cut label sheet.
    public var cropMarks: Bool = true
    public var showCaption: Bool = true
    public var quietZoneModules: Int = 4
    public var background: QRBackgroundMode = .whiteQuietZone
    public init() {}

    /// How many labels fit on one page with the current geometry.
    public var capacity: (columns: Int, rows: Int, perPage: Int) {
        let page = paper.sizePoints
        let margin = CGFloat(QRMeasurement.millimetersToPoints(marginMM))
        let spacing = CGFloat(QRMeasurement.millimetersToPoints(spacingMM))
        let labelSize = CGFloat(QRMeasurement.millimetersToPoints(labelSizeMM))
        let captionHeight: CGFloat = showCaption ? 12 : 0
        let cellWidth = labelSize
        let cellHeight = labelSize + captionHeight
        let usableWidth = page.width - 2 * margin
        let usableHeight = page.height - 2 * margin
        let columns = max(1, Int((usableWidth + spacing) / (cellWidth + spacing)))
        let rows = max(1, Int((usableHeight + spacing) / (cellHeight + spacing)))
        return (columns, rows, max(1, columns * rows))
    }
}

/// Lays out multiple labels on A4/Letter pages with margins, spacing, optional
/// cut guides and captions (spec §7.5). Fully vector.
public struct LabelSheetRenderer {

    public init() {}

    public func render(items: [LabelSheetItem], options: LabelSheetOptions) -> Data {
        let page = options.paper.sizePoints
        let margin = CGFloat(QRMeasurement.millimetersToPoints(options.marginMM))
        let spacing = CGFloat(QRMeasurement.millimetersToPoints(options.spacingMM))
        let labelSize = CGFloat(QRMeasurement.millimetersToPoints(options.labelSizeMM))
        let captionHeight: CGFloat = options.showCaption ? 12 : 0
        let cellWidth = labelSize
        let cellHeight = labelSize + captionHeight

        let usableWidth = page.width - 2 * margin
        let usableHeight = page.height - 2 * margin
        let columns = max(1, Int((usableWidth + spacing) / (cellWidth + spacing)))
        let rows = max(1, Int((usableHeight + spacing) / (cellHeight + spacing)))
        let perPage = max(1, columns * rows)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return data as Data }
        var mediaBox = CGRect(origin: .zero, size: page)
        let info = [kCGPDFContextCreator as String: "ProjectStock"] as CFDictionary
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, info) else { return data as Data }

        for (index, item) in items.enumerated() {
            let positionOnPage = index % perPage
            if positionOnPage == 0 {
                if index != 0 { ctx.endPDFPage() }
                ctx.beginPDFPage(nil)
            }
            let col = positionOnPage % columns
            let row = positionOnPage / columns

            // Top-left origin layout converted to PDF bottom-left coordinates.
            let cellX = margin + CGFloat(col) * (cellWidth + spacing)
            let cellTopY = page.height - margin - CGFloat(row) * (cellHeight + spacing)
            let cellBottomY = cellTopY - cellHeight

            let cellRect = CGRect(x: cellX, y: cellBottomY, width: cellWidth, height: cellHeight)
            if options.showCutGuides {
                ctx.saveGState()
                ctx.setStrokeColor(UIColor(white: 0.7, alpha: 1).cgColor)
                ctx.setLineWidth(0.25)
                ctx.stroke(cellRect)
                ctx.restoreGState()
            }
            if options.cropMarks {
                Self.drawCropMarks(cellRect, context: ctx)
            }

            let qrRect = CGRect(x: cellX, y: cellBottomY + captionHeight, width: labelSize, height: labelSize)
            QRVectorPDFRenderer.draw(matrix: item.matrix, quietZoneModules: options.quietZoneModules,
                                     in: qrRect, context: ctx, background: options.background)

            if options.showCaption, let caption = item.caption {
                let captionRect = CGRect(x: cellX, y: cellBottomY, width: cellWidth, height: captionHeight)
                QRVectorPDFRenderer.drawCaption(caption, in: captionRect, context: ctx)
            }
        }

        if !items.isEmpty { ctx.endPDFPage() }
        ctx.closePDF()
        return data as Data
    }

    /// Printer-style corner crop marks (トンボ): short L-shaped ticks just
    /// outside each of the label's four corners, so the sheet can be trimmed or
    /// lined up on a die-cut label sheet without a full border across the QR.
    private static func drawCropMarks(_ cell: CGRect, context: CGContext) {
        let markLen = CGFloat(QRMeasurement.millimetersToPoints(2.5))
        let gap = CGFloat(QRMeasurement.millimetersToPoints(0.6))
        context.saveGState()
        context.setStrokeColor(UIColor(white: 0.5, alpha: 1).cgColor)
        context.setLineWidth(0.3)
        // (corner, outward x sign, outward y sign)
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: cell.minX, y: cell.minY), -1, -1),
            (CGPoint(x: cell.maxX, y: cell.minY),  1, -1),
            (CGPoint(x: cell.minX, y: cell.maxY), -1,  1),
            (CGPoint(x: cell.maxX, y: cell.maxY),  1,  1),
        ]
        for (p, sx, sy) in corners {
            context.move(to: CGPoint(x: p.x + sx * gap, y: p.y))
            context.addLine(to: CGPoint(x: p.x + sx * (gap + markLen), y: p.y))
            context.move(to: CGPoint(x: p.x, y: p.y + sy * gap))
            context.addLine(to: CGPoint(x: p.x, y: p.y + sy * (gap + markLen)))
        }
        context.strokePath()
        context.restoreGState()
    }
}
