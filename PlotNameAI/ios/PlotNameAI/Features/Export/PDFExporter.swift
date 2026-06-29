import Foundation
import PDFKit
import UIKit

// MARK: - PDFExporter

/// ProjectBundle をネーム PDF に書き出す。各ページにコマ枠・番号・セリフを描く。
/// 右開き（右上→左→下）読み順でコマを配置する。
enum PDFExporter {

    /// A4 縦相当のページサイズ（pt）。
    static let pageSize = CGSize(width: 595, height: 842)

    /// PDF を生成し、保存先 URL を返す。
    static func export(bundle: ProjectBundle) throws -> URL {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let fileName = sanitized(bundle.project.title) + "_ネーム.pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        try renderer.writePDF(to: url) { context in
            // 表紙。
            context.beginPage()
            drawCover(bundle: bundle)

            // 各ページ。
            let plans = bundle.pagePlans.sorted { $0.pageNumber < $1.pageNumber }
            for plan in plans {
                context.beginPage()
                draw(page: plan, panels: bundle.panels(onPage: plan.pageNumber))
            }
        }
        return url
    }

    // MARK: Cover

    private static func drawCover(bundle: ProjectBundle) {
        let p = bundle.project
        let title = p.title.isEmpty ? "無題のネーム" : p.title

        draw(text: title, at: CGPoint(x: 48, y: 120), font: .boldSystemFont(ofSize: 32))
        draw(text: "フォーマット: \(p.format.displayName)　/　\(p.pageCount)ページ",
             at: CGPoint(x: 48, y: 180), font: .systemFont(ofSize: 16))
        if let brief = bundle.brief {
            draw(text: "ジャンル: \(brief.saveTheCatType.displayName)",
                 at: CGPoint(x: 48, y: 210), font: .systemFont(ofSize: 16))
            draw(text: "テーマ: \(brief.theme)",
                 at: CGPoint(x: 48, y: 236), font: .systemFont(ofSize: 16))
            drawWrapped(text: "ログライン: \(brief.logline)",
                        in: CGRect(x: 48, y: 270, width: pageSize.width - 96, height: 120),
                        font: .systemFont(ofSize: 14))
        }
        draw(text: "PlotName AI", at: CGPoint(x: 48, y: pageSize.height - 60),
             font: .systemFont(ofSize: 12), color: .gray)
    }

    // MARK: Page

    private static func draw(page: PagePlan, panels: [PanelSpec]) {
        // ヘッダ。
        let header = "P.\(page.pageNumber)　\(page.phaseEnum?.phaseName ?? "")　\(page.panelCount)コマ"
        draw(text: header, at: CGPoint(x: 36, y: 28), font: .boldSystemFont(ofSize: 14))
        draw(text: page.pageGoal, at: CGPoint(x: 36, y: 50),
             font: .systemFont(ofSize: 11), color: .darkGray)

        // ページ矩形（紙領域）。
        let margin: CGFloat = 36
        let top: CGFloat = 80
        let pageRect = CGRect(
            x: margin, y: top,
            width: pageSize.width - margin * 2,
            height: pageSize.height - top - margin
        )

        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setStrokeColor(UIColor.lightGray.cgColor)
        ctx.setLineWidth(0.5)
        ctx.stroke(pageRect)

        for panel in panels.sorted(by: { $0.panelNumber < $1.panelNumber }) {
            drawPanel(panel, in: pageRect)
        }

        // 引き。
        drawWrapped(text: "引き：\(page.lastPanelHook)",
                    in: CGRect(x: 36, y: pageSize.height - 30, width: pageSize.width - 72, height: 24),
                    font: .systemFont(ofSize: 10), color: .darkGray)
    }

    private static func drawPanel(_ panel: PanelSpec, in pageRect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let l = panel.layout
        // 右開き: X をミラーリング。
        let mirroredX = 1.0 - l.x - l.w
        let frame = CGRect(
            x: pageRect.minX + CGFloat(mirroredX) * pageRect.width,
            y: pageRect.minY + CGFloat(l.y) * pageRect.height,
            width: CGFloat(l.w) * pageRect.width,
            height: CGFloat(l.h) * pageRect.height
        )

        ctx.setStrokeColor(UIColor.black.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(frame.insetBy(dx: 2, dy: 2))

        // 番号バッジ（右上）。
        let badge = "\(panel.panelNumber)"
        draw(text: badge, at: CGPoint(x: frame.maxX - 18, y: frame.minY + 4),
             font: .boldSystemFont(ofSize: 11))

        // 説明・セリフ。
        var textY = frame.minY + 20
        if !panel.description.isEmpty {
            drawWrapped(text: panel.description,
                        in: CGRect(x: frame.minX + 6, y: textY, width: frame.width - 12, height: 36),
                        font: .systemFont(ofSize: 9), color: .darkGray)
            textY += 36
        }
        if !panel.dialogue.isEmpty {
            drawWrapped(text: "「\(panel.dialogue)」",
                        in: CGRect(x: frame.minX + 6, y: textY, width: frame.width - 12, height: 30),
                        font: .systemFont(ofSize: 10), color: .black)
        }
        if !panel.sfx.isEmpty {
            draw(text: panel.sfx, at: CGPoint(x: frame.minX + 6, y: frame.maxY - 18),
                 font: .boldSystemFont(ofSize: 12), color: .gray)
        }
    }

    // MARK: Text helpers

    private static func draw(text: String, at point: CGPoint, font: UIFont, color: UIColor = .black) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    private static func drawWrapped(text: String, in rect: CGRect, font: UIFont, color: UIColor = .black) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: style
        ]
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private static func sanitized(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = trimmed.isEmpty ? "PlotName" : trimmed
        return safe.replacingOccurrences(of: "/", with: "-")
    }
}
