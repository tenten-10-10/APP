import SwiftUI

// MARK: - PanelCanvasView

/// 1ページ分のコマを 0...1 の相対座標からページ矩形内に描画する。
/// マンガの右開き（右上→左→下）読み順でコマ番号バッジを表示する。
/// コマをタップすると選択コールバックが呼ばれる。
struct PanelCanvasView: View {

    let panels: [PanelSpec]
    let pageNumber: Int
    @Binding var selectedPanelID: PanelSpec.ID?

    /// ページの紙比率（B5相当 = 幅/高さ）。
    private let pageAspect: CGFloat = 0.71  // ≒ 182/257

    var body: some View {
        GeometryReader { geo in
            let pageRect = fittedPageRect(in: geo.size)

            ZStack(alignment: .topLeading) {
                // 用紙。
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                    )
                    .frame(width: pageRect.width, height: pageRect.height)
                    .position(x: pageRect.midX, y: pageRect.midY)
                    .shadow(radius: 3, y: 2)

                // 各コマ。
                ForEach(panels) { panel in
                    PanelShape(
                        panel: panel,
                        pageRect: pageRect,
                        isSelected: panel.id == selectedPanelID
                    )
                    .onTapGesture {
                        selectedPanelID = panel.id
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// 与えられた領域に紙比率を維持して収まるページ矩形を返す。
    private func fittedPageRect(in size: CGSize) -> CGRect {
        let padding: CGFloat = 12
        let availW = size.width - padding * 2
        let availH = size.height - padding * 2
        var w = availW
        var h = w / pageAspect
        if h > availH {
            h = availH
            w = h * pageAspect
        }
        let x = (size.width - w) / 2
        let y = (size.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

// MARK: - PanelShape

/// 1コマの矩形＋番号バッジ＋セリフプレビュー。
private struct PanelShape: View {
    let panel: PanelSpec
    let pageRect: CGRect
    let isSelected: Bool

    var body: some View {
        let frame = absoluteFrame()

        ZStack(alignment: .topTrailing) {
            // コマ枠。
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isSelected ? Color.accentColor : Color.primary,
                                lineWidth: isSelected ? 3 : 1.5)
                )

            // 内容（説明＋セリフ）。
            VStack(alignment: .leading, spacing: 2) {
                if !panel.dialogue.isEmpty {
                    Text(panel.dialogue)
                        .font(.system(size: 9))
                        .lineLimit(2)
                        .padding(3)
                        .background(Color(.systemBackground).opacity(0.85),
                                    in: RoundedRectangle(cornerRadius: 3))
                }
                Spacer(minLength: 0)
                if !panel.sfx.isEmpty {
                    Text(panel.sfx)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(4)

            // 読み順バッジ（右上）。
            Text("\(panel.panelNumber)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor, in: Circle())
                .padding(3)
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }

    /// 0...1 のレイアウトを実ピクセル座標に変換。
    /// 右開きのため、X は反転して右側を panelNumber=1 起点に見せる。
    private func absoluteFrame() -> CGRect {
        let l = panel.layout
        // 右開き: x をミラーリング（画面右が物語の先頭）。
        let mirroredX = 1.0 - l.x - l.w
        let x = pageRect.minX + CGFloat(mirroredX) * pageRect.width
        let y = pageRect.minY + CGFloat(l.y) * pageRect.height
        let w = CGFloat(l.w) * pageRect.width
        let h = CGFloat(l.h) * pageRect.height
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

#Preview {
    PanelCanvasView(
        panels: SampleData.bundle.panels(onPage: 1),
        pageNumber: 1,
        selectedPanelID: .constant(nil)
    )
    .frame(width: 360, height: 500)
    .padding()
}
