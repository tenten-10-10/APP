import SwiftUI
#if canImport(PencilKit)
import PencilKit
#endif

// MARK: - AnnotationCanvasView

#if canImport(PencilKit)

/// PKCanvasView を SwiftUI でラップした赤入れ（Apple Pencil 注釈）オーバーレイ。
/// ネームのページ上に重ねて使う。描画は PKDrawing.dataRepresentation() で Data 化し、
/// バインディング経由で呼び出し側が永続化する。
/// iPad（regular 幅）専用想定。
struct AnnotationCanvasView: UIViewRepresentable {

    /// 永続化用の PKDrawing データ。空なら白紙。
    @Binding var drawingData: Data
    /// 描画可能か（false なら閲覧のみ＝下のレイアウトをタップ操作させる）。
    var isActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // 赤ペンを既定にする（赤入れ）。
        canvas.tool = PKInkingTool(.pen, color: .systemRed, width: 4)
        canvas.drawingPolicy = .anyInput   // 指でも描けるようにする（Pencil 必須にしない）。
        canvas.delegate = context.coordinator

        // 既存の描画を復元。
        if let drawing = try? PKDrawing(data: drawingData) {
            canvas.drawing = drawing
        }
        canvas.isUserInteractionEnabled = isActive
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // 操作可否の切り替え。
        canvas.isUserInteractionEnabled = isActive

        // 外部からデータが差し替わった場合のみ再読み込み（自分の編集ループは避ける）。
        if !context.coordinator.isApplyingLocalChange,
           let incoming = try? PKDrawing(data: drawingData),
           incoming.dataRepresentation() != canvas.drawing.dataRepresentation() {
            canvas.drawing = incoming
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let parent: AnnotationCanvasView
        /// 自分の編集による更新中フラグ（updateUIView の上書きを防ぐ）。
        var isApplyingLocalChange = false

        init(_ parent: AnnotationCanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            isApplyingLocalChange = true
            parent.drawingData = canvasView.drawing.dataRepresentation()
            isApplyingLocalChange = false
        }
    }
}

#else

/// PencilKit が無いプラットフォーム向けのフォールバック（何も描かない）。
struct AnnotationCanvasView: View {
    @Binding var drawingData: Data
    var isActive: Bool
    var body: some View { Color.clear }
}

#endif
