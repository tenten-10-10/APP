import SwiftUI

// MARK: - Theme

/// アプリ共通の見た目ヘルパー。
enum Theme {

    /// フェーズ番号に応じた色（1...13）。三幕構成のおおまかな色分け。
    static func color(forPhase number: Int) -> Color {
        switch number {
        case 1...3:  return .blue        // 第一幕
        case 4...7:  return .green       // 第二幕前半
        case 8...10: return .orange      // 第二幕後半
        case 11...13: return .red        // 第三幕
        default:     return .gray
        }
    }

    /// 感情価（-5...+5）を 0...1 に正規化。
    static func normalizedEmotion(_ value: Int) -> Double {
        (Double(value) + 5.0) / 10.0
    }

    /// 密度に応じた色。
    static func color(forDensity density: Density) -> Color {
        switch density {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }
}

// MARK: - Reusable chip

/// 小さなラベルチップ。
struct Chip: View {
    let text: String
    var color: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
