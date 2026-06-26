import SwiftUI

/// Shared brand colours and reusable styling so onboarding, the dashboard and
/// primary call-to-actions stay visually consistent.
enum Brand {
    /// The app's accent (matches `AccentColor` / the app icon).
    static let primary = Color.accentColor

    /// Diagonal brand gradient used behind hero artwork and the app icon.
    static var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 46 / 255, green: 134 / 255, blue: 230 / 255),
                Color(red: 20 / 255, green: 84 / 255, blue: 184 / 255),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Full-width filled primary button (brand colour, white label).
struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 26)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(enabled ? Brand.primary : Color.secondary)
            )
            .foregroundColor(.white)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

/// Small paging dots used by the onboarding carousel.
struct PageDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == index ? Brand.primary : Color(.tertiaryLabel))
                    .frame(width: i == index ? 9 : 7, height: i == index ? 9 : 7)
                    .animation(.easeInOut(duration: 0.2), value: index)
            }
        }
        .accessibilityHidden(true)
    }
}
