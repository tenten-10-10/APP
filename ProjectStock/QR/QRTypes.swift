import Foundation
import CoreGraphics

/// Unit conversion constants used throughout QR sizing math.
enum QRMeasurement {
    static let mmPerInch: Double = 25.4
    static let pointsPerInch: Double = 72.0

    static func millimetersToPoints(_ mm: Double) -> Double { mm / mmPerInch * pointsPerInch }
    static func millimetersToPixels(_ mm: Double, dpi: Int) -> Double { mm / mmPerInch * Double(dpi) }
    static func pixelsToMillimeters(_ px: Double, dpi: Int) -> Double { px / Double(dpi) * mmPerInch }
}

/// QR error-correction level. Raw values match `CIQRCodeGenerator`'s
/// `inputCorrectionLevel` input.
public enum QRErrorCorrectionLevel: String, CaseIterable, Identifiable {
    case low = "L"
    case medium = "M"
    case quartile = "Q"
    case high = "H"

    public var id: String { rawValue }

    /// Approximate recoverable fraction, used by the scanability estimate.
    var recoveryFraction: Double {
        switch self {
        case .low: return 0.07
        case .medium: return 0.15
        case .quartile: return 0.25
        case .high: return 0.30
        }
    }

    var localizedTitle: String {
        switch self {
        case .low:      return NSLocalizedString("L（約7%）", comment: "")
        case .medium:   return NSLocalizedString("M（約15%）", comment: "")
        case .quartile: return NSLocalizedString("Q（約25%）", comment: "")
        case .high:     return NSLocalizedString("H（約30%）", comment: "")
        }
    }
}

/// Physical size presets (spec §7.1). Sizes are the total printed edge length
/// of the QR including its quiet zone.
public enum QRSizePreset: String, CaseIterable, Identifiable {
    case small      // 8 mm
    case medium     // 16 mm
    case large      // 28 mm
    case custom

    public var id: String { rawValue }

    var defaultMillimeters: Double {
        switch self {
        case .small: return 8
        case .medium: return 16
        case .large: return 28
        case .custom: return 20
        }
    }

    /// Suggested error correction for the preset (spec §7.1).
    var suggestedECC: QRErrorCorrectionLevel {
        switch self {
        case .small: return .medium      // L or M; we default to M for safety
        case .medium: return .medium
        case .large: return .quartile
        case .custom: return .medium
        }
    }

    var localizedTitle: String {
        switch self {
        case .small:  return NSLocalizedString("小 (8mm)", comment: "")
        case .medium: return NSLocalizedString("中 (16mm)", comment: "")
        case .large:  return NSLocalizedString("大 (28mm)", comment: "")
        case .custom: return NSLocalizedString("カスタム", comment: "")
        }
    }

    /// Allowed custom range (spec §7.1: 5–100 mm).
    static let customRange: ClosedRange<Double> = 5...100
}

/// Background handling for exports (spec §7.3).
public enum QRBackgroundMode: String, CaseIterable, Identifiable {
    /// Quiet zone painted white/opaque, only the outside is transparent (default).
    case whiteQuietZone
    /// Fully transparent including the quiet zone — risky, shows a warning.
    case fullyTransparent
    /// Solid white background everywhere (for EPS / print on dark stock).
    case solidWhite

    public var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .whiteQuietZone:   return NSLocalizedString("白の余白を保持（推奨）", comment: "")
        case .fullyTransparent: return NSLocalizedString("余白も透過（注意）", comment: "")
        case .solidWhite:       return NSLocalizedString("全体を白背景", comment: "")
        }
    }
}

/// A fully resolved description of one label to render.
public struct QRRenderSpec {
    public var code: String
    public var totalSizeMM: Double
    public var errorCorrection: QRErrorCorrectionLevel
    public var dpi: Int
    public var quietZoneModules: Int
    public var background: QRBackgroundMode

    public init(code: String,
                totalSizeMM: Double,
                errorCorrection: QRErrorCorrectionLevel,
                dpi: Int = 600,
                quietZoneModules: Int = 4,
                background: QRBackgroundMode = .whiteQuietZone) {
        self.code = code
        self.totalSizeMM = totalSizeMM
        self.errorCorrection = errorCorrection
        self.dpi = dpi
        self.quietZoneModules = quietZoneModules
        self.background = background
    }
}

/// Export file format (spec §1, §7).
public enum QRExportFormat: String, CaseIterable, Identifiable {
    case png
    case pdf
    case eps
    case svg

    public var id: String { rawValue }
    var fileExtension: String { rawValue }
    var localizedTitle: String { rawValue.uppercased() }
}
