import SwiftUI

extension ProjectColor {
    var color: Color {
        switch self {
        case .blue:   return .blue
        case .green:  return .green
        case .orange: return .orange
        case .red:    return .red
        case .purple: return .purple
        case .teal:   return .teal
        case .pink:   return .pink
        case .gray:   return .gray
        }
    }

    var localizedTitle: String {
        switch self {
        case .blue:   return NSLocalizedString("青", comment: "")
        case .green:  return NSLocalizedString("緑", comment: "")
        case .orange: return NSLocalizedString("橙", comment: "")
        case .red:    return NSLocalizedString("赤", comment: "")
        case .purple: return NSLocalizedString("紫", comment: "")
        case .teal:   return NSLocalizedString("青緑", comment: "")
        case .pink:   return NSLocalizedString("桃", comment: "")
        case .gray:   return NSLocalizedString("灰", comment: "")
        }
    }
}

extension Double {
    /// Compact quantity formatting: drops the decimal for whole numbers.
    var quantityString: String {
        if self == rounded() { return String(Int(self)) }
        return String(format: "%.2f", self)
    }
}
