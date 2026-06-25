import Foundation

/// Hand-writes ASCII Encapsulated PostScript (spec §7.6). It does not embed any
/// raster image and does not rely on the concept of transparency — dark modules
/// are emitted as `rectfill` operations in PostScript points. Horizontal runs
/// are merged to keep the file compact.
public struct QREPSRenderer {

    public init() {}

    /// Returns EPS source as UTF-8 data.
    public func renderEPS(matrix: QRCodeMatrix, spec: QRRenderSpec, title: String = "ProjectStock QR") -> Data {
        Data(renderEPSString(matrix: matrix, spec: spec, title: title).utf8)
    }

    public func renderEPSString(matrix: QRCodeMatrix, spec: QRRenderSpec, title: String = "ProjectStock QR") -> String {
        let padded = matrix.paddedGrid(quietZoneModules: spec.quietZoneModules)
        let total = padded.totalModuleCount
        let sizePts = QRMeasurement.millimetersToPoints(spec.totalSizeMM)
        let module = sizePts / Double(total)
        let boundingW = Int(ceil(sizePts))
        let boundingH = Int(ceil(sizePts))

        var out = String()
        out.reserveCapacity(2048)
        out += "%!PS-Adobe-3.0 EPSF-3.0\n"
        out += "%%Creator: ProjectStock\n"
        out += "%%Title: \(sanitize(title))\n"
        out += "%%CreationDate: (generated)\n"
        out += "%%BoundingBox: 0 0 \(boundingW) \(boundingH)\n"
        out += String(format: "%%%%HiResBoundingBox: 0 0 %.4f %.4f\n", sizePts, sizePts)
        out += "%%LanguageLevel: 2\n"
        out += "%%Pages: 1\n"
        out += "%%EndComments\n"
        out += "%%Page: 1 1\n"
        out += "gsave\n"

        // Background. EPS has no alpha; for the "transparent" mode we simply
        // omit the white fill so whatever the medium is shows through.
        switch spec.background {
        case .whiteQuietZone, .solidWhite:
            out += "1 setgray\n"
            out += String(format: "0 0 %.4f %.4f rectfill\n", sizePts, sizePts)
        case .fullyTransparent:
            break
        }

        out += "0 setgray\n"
        for row in 0..<total {
            // PostScript origin is bottom-left; row 0 is the visual top.
            let y = Double(total - 1 - row) * module
            for run in padded.darkRuns(inRow: row) {
                let x = Double(run.start) * module
                let w = Double(run.length) * module
                out += String(format: "%.4f %.4f %.4f %.4f rectfill\n", x, y, w, module)
            }
        }

        out += "grestore\n"
        out += "showpage\n"
        out += "%%EOF\n"
        return out
    }

    /// Strip characters that would break a DSC comment line.
    private func sanitize(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
    }
}
