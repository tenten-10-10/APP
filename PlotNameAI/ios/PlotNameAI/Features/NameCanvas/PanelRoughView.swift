import SwiftUI

// MARK: - PanelRoughView

/// PanelRough（ラフ記述子）を線画として描画するプレースホルダー。
/// 実画像ではなく、SF Symbol ＋ 簡易図形（RoughShape）でラフの雰囲気を表現する。
struct PanelRoughView: View {

    let rough: PanelRough
    /// キャプションを表示するか。
    var showsCaption: Bool = true

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack {
                    // 背景。
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.secondarySystemBackground))

                    // 簡易図形（線画）。
                    ForEach(Array(rough.shapes.enumerated()), id: \.offset) { _, shape in
                        shapeView(shape, in: geo.size)
                    }

                    // 中央のシンボル。
                    Image(systemName: rough.symbolName)
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.28))
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(0.71, contentMode: .fit)

            if showsCaption {
                Text(rough.caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: Shape drawing

    @ViewBuilder
    private func shapeView(_ shape: RoughShape, in size: CGSize) -> some View {
        let rect = CGRect(
            x: shape.x * size.width,
            y: shape.y * size.height,
            width: shape.w * size.width,
            height: max(1, shape.h * size.height)
        )
        switch shape.kind {
        case .rectangle:
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        case .ellipse:
            Ellipse()
                .stroke(Color.secondary.opacity(0.6), lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        case .line:
            // 水平線（地平線など）。h は無視して midY を使う。
            Rectangle()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: rect.width, height: 1.5)
                .position(x: rect.midX, y: rect.minY)
        }
    }
}

#Preview {
    PanelRoughView(
        rough: PanelRough(
            panelId: UUID(),
            symbolName: "figure.run",
            caption: "対決／クローズアップ・あおり：ハル",
            seed: 42,
            shapes: [
                RoughShape(kind: .rectangle, x: 0.1, y: 0.1, w: 0.8, h: 0.8),
                RoughShape(kind: .ellipse, x: 0.35, y: 0.2, w: 0.32, h: 0.32),
                RoughShape(kind: .line, x: 0.06, y: 0.7, w: 0.88, h: 0)
            ]
        )
    )
    .frame(width: 220)
    .padding()
}
