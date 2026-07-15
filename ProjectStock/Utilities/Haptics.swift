import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Thin wrapper over UIFeedbackGenerator, gated by the user's Haptics setting
/// (spec §12.7) and silenced during UI tests.
enum Haptics {

    static func success() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func warning() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    static func error() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }

    static func tap() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private static var isEnabled: Bool {
        guard !AppConfig.isUITesting else { return false }
        return AppSettings.shared.hapticsEnabled
    }
}
