import SwiftUI

/// Compact sync-state chip (spec §13). Uses an icon + text, never color alone
/// (spec §15 accessibility).
struct SyncStatusBadge: View {
    let state: SyncState
    var body: some View {
        Label(state.localizedTitle, systemImage: state.systemImageName)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(.secondarySystemBackground)))
            .foregroundColor(state.isError ? .red : .secondary)
            .accessibilityLabel(Text(NSLocalizedString("同期状態", comment: "")) + Text(": ") + Text(state.localizedTitle))
    }
}

/// Share permission chip (spec §12.2). Icon + label so it is not color-only.
struct SharePermissionBadge: View {
    let permission: SharePermission
    var body: some View {
        Label(permission.badgeTitle, systemImage: icon)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(.secondarySystemBackground)))
            .foregroundColor(.secondary)
            .accessibilityLabel(Text(permission.badgeTitle))
    }
    private var icon: String {
        switch permission {
        case .notShared: return "iphone"
        case .owner:     return "person.2.fill"
        case .readWrite: return "pencil.and.outline"
        case .readOnly:  return "eye"
        }
    }
}

/// Low-stock indicator: icon + text, not color-only (spec §15).
struct LowStockChip: View {
    var body: some View {
        Label(NSLocalizedString("要補充", comment: ""), systemImage: "exclamationmark.triangle.fill")
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(Color.orange.opacity(0.18)))
            .foregroundColor(.orange)
            .accessibilityLabel(Text(NSLocalizedString("在庫が最低数量以下です", comment: "")))
    }
}

struct ScanabilityChip: View {
    let rating: QRScanabilityEvaluator.Rating
    var body: some View {
        Label(rating.localizedTitle, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundColor(tint)
            .accessibilityLabel(Text(NSLocalizedString("読取評価", comment: "")) + Text(": ") + Text(rating.localizedTitle))
    }
    private var icon: String {
        switch rating {
        case .recommended: return "checkmark.seal"
        case .caution: return "exclamationmark.triangle"
        case .notRecommended: return "xmark.octagon"
        }
    }
    private var tint: Color {
        switch rating {
        case .recommended: return .green
        case .caution: return .orange
        case .notRecommended: return .red
        }
    }
}
