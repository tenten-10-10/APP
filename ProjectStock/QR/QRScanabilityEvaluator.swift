import Foundation

/// The "QR Fit" / read-reliability engine (spec §4.1). It does NOT promise a
/// QR will scan — it surfaces the geometry and flags risky combinations early
/// (tiny modules, sub-8 mm sizes, insufficient print resolution, short quiet
/// zone) so the user verifies on the calibration sheet.
public struct QRScanabilityEvaluator {

    public enum Rating: String {
        case recommended
        case caution
        case notRecommended

        public var localizedTitle: String {
            switch self {
            case .recommended:    return NSLocalizedString("推奨", comment: "")
            case .caution:        return NSLocalizedString("注意", comment: "")
            case .notRecommended: return NSLocalizedString("非推奨", comment: "")
            }
        }

        var severity: Int {
            switch self {
            case .recommended: return 0
            case .caution: return 1
            case .notRecommended: return 2
            }
        }

        static func worst(_ a: Rating, _ b: Rating) -> Rating { a.severity >= b.severity ? a : b }
    }

    public struct Report {
        public let version: Int
        public let dataModuleCount: Int
        public let totalModuleCount: Int
        public let moduleSizeMM: Double
        public let quietZoneModules: Int
        public let quietZoneMM: Double
        public let errorCorrection: QRErrorCorrectionLevel
        public let dpi: Int
        public let modulePixels: Double
        public let payloadLength: Int
        public let rating: Rating
        public let warnings: [String]
    }

    public init() {}

    public func evaluate(matrix: QRCodeMatrix, spec: QRRenderSpec) -> Report {
        let totalModules = matrix.moduleCount + 2 * spec.quietZoneModules
        let moduleSizeMM = spec.totalSizeMM / Double(totalModules)
        let quietZoneMM = moduleSizeMM * Double(spec.quietZoneModules)
        let modulePixels = QRMeasurement.millimetersToPixels(moduleSizeMM, dpi: spec.dpi)

        var rating = Rating.recommended
        var warnings: [String] = []

        if spec.totalSizeMM < 8 {
            rating = .worst(rating, .caution)
            warnings.append(NSLocalizedString("8mm未満のサイズです。印刷校正シートで実機確認を強く推奨します。", comment: ""))
        }

        // Physical module size thresholds.
        if moduleSizeMM < 0.25 {
            rating = .worst(rating, .notRecommended)
            warnings.append(NSLocalizedString("1モジュールが0.25mm未満です。多くのカメラで読み取れません。", comment: ""))
        } else if moduleSizeMM < 0.40 {
            rating = .worst(rating, .caution)
            warnings.append(NSLocalizedString("1モジュールが小さめです。近距離・良好な照明が必要です。", comment: ""))
        }

        // Printer resolution: need enough pixels per module.
        if modulePixels < 2 {
            rating = .worst(rating, .notRecommended)
            warnings.append(NSLocalizedString("この解像度では1モジュールが2ピクセル未満になり、印刷がつぶれます。", comment: ""))
        } else if modulePixels < 4 {
            rating = .worst(rating, .caution)
            warnings.append(NSLocalizedString("1モジュールあたりのピクセル数が少なめです。DPIを上げると安定します。", comment: ""))
        }

        // Quiet zone.
        if spec.quietZoneModules < 4 {
            rating = .worst(rating, .caution)
            warnings.append(NSLocalizedString("Quiet Zoneが4モジュール未満です。読取が不安定になります。", comment: ""))
        }

        // Error correction vs. size tradeoff hint.
        if spec.errorCorrection == .high && spec.totalSizeMM < 12 {
            warnings.append(NSLocalizedString("誤り訂正Hはモジュール数を増やします。小さいラベルではサイズと両立しにくくなります。", comment: ""))
        }

        if warnings.isEmpty {
            warnings.append(NSLocalizedString("一般的な条件では読取に余裕があります。", comment: ""))
        }

        return Report(version: matrix.version,
                      dataModuleCount: matrix.moduleCount,
                      totalModuleCount: totalModules,
                      moduleSizeMM: moduleSizeMM,
                      quietZoneModules: spec.quietZoneModules,
                      quietZoneMM: quietZoneMM,
                      errorCorrection: spec.errorCorrection,
                      dpi: spec.dpi,
                      modulePixels: modulePixels,
                      payloadLength: AppConfig.qrPayload(for: spec.code).count,
                      rating: rating,
                      warnings: warnings)
    }
}
