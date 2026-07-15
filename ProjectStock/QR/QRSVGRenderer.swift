import Foundation

/// Optional vector SVG output. The spec only requires that the export pipeline
/// be *structured* so SVG can be added (spec §1); this is a working, compact
/// implementation that merges horizontal runs into `<rect>` elements.
public struct QRSVGRenderer {

    public init() {}

    public func renderSVG(matrix: QRCodeMatrix, spec: QRRenderSpec) -> Data {
        Data(renderSVGString(matrix: matrix, spec: spec).utf8)
    }

    public func renderSVGString(matrix: QRCodeMatrix, spec: QRRenderSpec) -> String {
        let padded = matrix.paddedGrid(quietZoneModules: spec.quietZoneModules)
        let total = padded.totalModuleCount
        let sizeMM = spec.totalSizeMM

        var out = String()
        out += #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
        out += "<svg xmlns=\"http://www.w3.org/2000/svg\" "
        out += "width=\"\(format(sizeMM))mm\" height=\"\(format(sizeMM))mm\" "
        out += "viewBox=\"0 0 \(total) \(total)\" shape-rendering=\"crispEdges\">\n"

        switch spec.background {
        case .whiteQuietZone, .solidWhite:
            out += "<rect x=\"0\" y=\"0\" width=\"\(total)\" height=\"\(total)\" fill=\"#FFFFFF\"/>\n"
        case .fullyTransparent:
            break
        }

        out += "<g fill=\"#000000\">\n"
        for row in 0..<total {
            for run in padded.darkRuns(inRow: row) {
                out += "<rect x=\"\(run.start)\" y=\"\(row)\" width=\"\(run.length)\" height=\"1\"/>\n"
            }
        }
        out += "</g>\n</svg>\n"
        return out
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
