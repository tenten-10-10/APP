import Foundation
import Combine

/// User-facing preferences, persisted in `UserDefaults`. Pure preferences only
/// — no inventory data lives here.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.operatorDisplayName = defaults.string(forKey: Keys.operatorName)
            ?? NSLocalizedString("担当者", comment: "default operator name")
        self.hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        self.defaultSizePresetRaw = defaults.string(forKey: Keys.sizePreset) ?? QRSizePreset.medium.rawValue
        self.defaultDPI = defaults.object(forKey: Keys.dpi) as? Int ?? 600
        self.defaultErrorCorrectionRaw = defaults.string(forKey: Keys.ecc) ?? QRErrorCorrectionLevel.medium.rawValue
        self.continuousScanByDefault = defaults.object(forKey: Keys.continuousScan) as? Bool ?? false
    }

    @Published var operatorDisplayName: String {
        didSet { defaults.set(operatorDisplayName, forKey: Keys.operatorName) }
    }

    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) }
    }

    @Published var defaultSizePresetRaw: String {
        didSet { defaults.set(defaultSizePresetRaw, forKey: Keys.sizePreset) }
    }

    @Published var defaultDPI: Int {
        didSet { defaults.set(defaultDPI, forKey: Keys.dpi) }
    }

    @Published var defaultErrorCorrectionRaw: String {
        didSet { defaults.set(defaultErrorCorrectionRaw, forKey: Keys.ecc) }
    }

    @Published var continuousScanByDefault: Bool {
        didSet { defaults.set(continuousScanByDefault, forKey: Keys.continuousScan) }
    }

    // Convenience typed accessors

    var defaultSizePreset: QRSizePreset {
        get { QRSizePreset(rawValue: defaultSizePresetRaw) ?? .medium }
        set { defaultSizePresetRaw = newValue.rawValue }
    }

    var defaultErrorCorrection: QRErrorCorrectionLevel {
        get { QRErrorCorrectionLevel(rawValue: defaultErrorCorrectionRaw) ?? .medium }
        set { defaultErrorCorrectionRaw = newValue.rawValue }
    }

    /// Trimmed, non-empty operator name suitable for stamping on events.
    var effectiveOperatorName: String {
        let trimmed = operatorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("担当者", comment: "") : trimmed
    }

    private enum Keys {
        static let operatorName = "settings.operatorName"
        static let haptics = "settings.haptics"
        static let sizePreset = "settings.defaultSizePreset"
        static let dpi = "settings.defaultDPI"
        static let ecc = "settings.defaultECC"
        static let continuousScan = "settings.continuousScan"
    }
}
