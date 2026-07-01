import SwiftUI

/// Shared brand colours and reusable styling so onboarding, the dashboard and
/// primary call-to-actions stay visually consistent.
enum Brand {
    /// The app's accent (matches `AccentColor` / the app icon).
    static let primary = Color.accentColor

    /// Diagonal brand gradient (dark olive) used behind hero artwork.
    static var gradient: LinearGradient {
        LinearGradient(
            colors: [gradientStart, gradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Lighter olive used at the gradient's top-leading corner.
    static let gradientStart = Color(red: 110 / 255, green: 124 / 255, blue: 72 / 255)
    /// Deep olive used at the gradient's bottom-trailing corner.
    static let gradientEnd = Color(red: 60 / 255, green: 72 / 255, blue: 38 / 255)
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

/// Full-width tinted secondary button (light brand fill, brand-coloured label).
/// Pairs with `PrimaryButtonStyle` for a two-action hero.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 26)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Brand.primary.opacity(0.12))
            )
            .foregroundColor(Brand.primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
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
