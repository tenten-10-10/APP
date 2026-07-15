import XCTest
import CoreGraphics
@testable import ProjectStock

final class QRRenderingTests: XCTestCase {

    private let encoder = CoreImageQREncoder()
    private let sampleCode = "IQ0123456789ABCDEF"

    // MARK: - Matrix & quiet zone

    func testMatrixIsWellFormedSquare() throws {
        let matrix = try encoder.encode(sampleCode, errorCorrection: .medium)
        XCTAssertTrue(matrix.isWellFormed)
        XCTAssertEqual(matrix.modules.count, matrix.moduleCount)
        XCTAssertTrue(matrix.modules.allSatisfy { $0.count == matrix.moduleCount })
        XCTAssertEqual((matrix.moduleCount - 17) % 4, 0, "サイズはQRバージョンに一致する")
    }

    func testQuietZoneIsFourModules() throws {
        let matrix = try encoder.encode(sampleCode, errorCorrection: .medium)
        let padded = matrix.paddedGrid(quietZoneModules: 4)
        XCTAssertEqual(padded.totalModuleCount, matrix.moduleCount + 8)
        // The outer 4-module ring must be entirely light.
        for i in 0..<padded.totalModuleCount {
            for q in 0..<4 {
                XCTAssertFalse(padded.isDark(row: q, col: i), "上端のQuiet Zoneが暗い")
                XCTAssertFalse(padded.isDark(row: padded.totalModuleCount - 1 - q, col: i), "下端のQuiet Zoneが暗い")
                XCTAssertFalse(padded.isDark(row: i, col: q), "左端のQuiet Zoneが暗い")
                XCTAssertFalse(padded.isDark(row: i, col: padded.totalModuleCount - 1 - q), "右端のQuiet Zoneが暗い")
            }
        }
    }

    // MARK: - PNG

    func testPNGIntegerScalingAndDimensions() throws {
        let matrix = try encoder.encode(sampleCode, errorCorrection: .medium)
        let spec = QRRenderSpec(code: sampleCode, totalSizeMM: 16, errorCorrection: .medium, dpi: 600)
        let result = try QRRasterRenderer().renderPNG(matrix: matrix, spec: spec)

        let total = matrix.moduleCount + 8
        XCTAssertGreaterThanOrEqual(result.geometry.modulePixelSize, 1)
        XCTAssertEqual(result.geometry.pixelDimension, result.geometry.modulePixelSize * total,
                       "ピクセル寸法はモジュール数の整数倍")
        XCTAssertEqual(result.geometry.pixelDimension % total, 0, "モジュールは整数ピクセル")
        XCTAssertEqual(result.cgImage.width, result.geometry.pixelDimension)
        XCTAssertEqual(result.cgImage.height, result.geometry.pixelDimension)
        XCTAssertFalse(result.pngData.isEmpty)
        // PNG magic number.
        XCTAssertEqual(Array(result.pngData.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testPNGHasAlphaChannel() throws {
        let matrix = try encoder.encode(sampleCode, errorCorrection: .medium)
        let spec = QRRenderSpec(code: sampleCode, totalSizeMM: 16, errorCorrection: .medium,
                                dpi: 300, background: .fullyTransparent)
        let result = try QRRasterRenderer().renderPNG(matrix: matrix, spec: spec)
        let alphaInfo = result.cgImage.alphaInfo
        XCTAssertNotEqual(alphaInfo, .none, "透過PNGはアルファチャンネルを持つ")
    }

    // MARK: - PDF

    func testPDFPageSizeMatchesRequestedMillimeters() throws {
        let matrix = try encoder.encode(sampleCode, errorCorrection: .medium)
        let sizeMM = 28.0
        let spec = QRRenderSpec(code: sampleCode, totalSizeMM: sizeMM, errorCorrection: .quartile)
        let data = try QRVectorPDFRenderer().renderSingleLabel(matrix: matrix, spec: spec)

        XCTAssertEqual(Array(data.prefix(4)), Array("%PDF".utf8))
        let provider = CGDataProvider(data: data as CFData)!
        let document = CGPDFDocument(provider)!
        let page = document.page(at: 1)!
        let box = page.getBoxRect(.mediaBox)
        let expectedPts = CGFloat(QRMeasurement.millimetersToPoints(sizeMM))
        XCTAssertEqual(box.width, expectedPts, accuracy: 0.5, "PDFページ幅は指定mmと一致する")
        XCTAssertEqual(box.height, expectedPts, accuracy: 0.5, "PDFページ高さは指定mmと一致する")
    }

    // MARK: - EPS

    func testEPSHeaderAndBoundingBox() throws {
        let matrix = try encoder.encode(sampleCode, errorCorrection: .medium)
        let sizeMM = 16.0
        let spec = QRRenderSpec(code: sampleCode, totalSizeMM: sizeMM, errorCorrection: .medium)
        let eps = QREPSRenderer().renderEPSString(matrix: matrix, spec: spec)

        XCTAssertTrue(eps.hasPrefix("%!PS-Adobe-3.0 EPSF-3.0"), "EPSヘッダーが正しい")
        let expected = Int(ceil(QRMeasurement.millimetersToPoints(sizeMM)))
        XCTAssertTrue(eps.contains("%%BoundingBox: 0 0 \(expected) \(expected)"), "BoundingBoxが正しい")
        XCTAssertTrue(eps.contains("rectfill"), "ベクター矩形で描画される")
        XCTAssertTrue(eps.contains("%%EOF"))
    }

    func testEPSTransparentBackgroundOmitsWhiteFill() throws {
        let matrix = try encoder.encode(sampleCode, errorCorrection: .medium)
        let spec = QRRenderSpec(code: sampleCode, totalSizeMM: 16, errorCorrection: .medium,
                                background: .fullyTransparent)
        let eps = QREPSRenderer().renderEPSString(matrix: matrix, spec: spec)
        XCTAssertFalse(eps.contains("1 setgray"), "透過指定では白背景を描かない")
    }
}
