import SwiftUI

// MARK: - PhaseGridView

/// 13フェーズをグリッド表示し、感情曲線も合わせて見せる。
struct PhaseGridView: View {

    @Environment(ProjectStore.self) private var store

    private var cards: [PhaseCard] {
        (store.selectedBundle?.phaseCards ?? []).sorted { $0.phaseNumber < $1.phaseNumber }
    }

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 12)]

    var body: some View {
        ScrollView {
            if cards.isEmpty {
                ContentUnavailableView(
                    "フェーズ未生成",
                    systemImage: "square.grid.3x3",
                    description: Text("プロジェクトを生成すると13フェーズが表示されます。")
                )
                .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    EmotionCurveView(cards: cards)
                        .frame(height: 120)
                        .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(cards) { card in
                            NavigationLink {
                                PhaseDetailView(card: card)
                            } label: {
                                PhaseCardCell(card: card)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("13フェーズ構成")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PhaseCardCell

private struct PhaseCardCell: View {
    let card: PhaseCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(card.phaseNumber)")
                    .font(.caption.bold())
                    .frame(width: 24, height: 24)
                    .background(Theme.color(forPhase: card.phaseNumber), in: Circle())
                    .foregroundStyle(.white)
                Text(card.phaseName)
                    .font(.headline)
                Spacer()
            }
            Text(card.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            HStack {
                Chip(text: "P\(card.pages.first ?? 0)-\(card.pages.last ?? 0)", color: .gray)
                Chip(text: "感情 \(card.emotionalValue >= 0 ? "+" : "")\(card.emotionalValue)",
                     color: Theme.color(forPhase: card.phaseNumber))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .topTrailing) {
            if card.weaknessAlert != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(8)
            }
        }
    }
}

// MARK: - PhaseDetailView

private struct PhaseDetailView: View {
    let card: PhaseCard

    var body: some View {
        List {
            Section("概要") {
                Text(card.summary)
                LabeledContent("役割", value: card.function)
                LabeledContent("感情価", value: "\(card.emotionalValue)")
                LabeledContent("ページ", value: card.pages.map(String.init).joined(separator: ", "))
            }
            Section("必ず描く") {
                ForEach(card.mustShow, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle")
                }
            }
            if let alert = card.weaknessAlert {
                Section("注意") {
                    Label(alert, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("\(card.phaseNumber). \(card.phaseName)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - EmotionCurveView

/// 13フェーズの感情価を折れ線で描く。
private struct EmotionCurveView: View {
    let cards: [PhaseCard]

    var body: some View {
        GeometryReader { geo in
            let points = curvePoints(in: geo.size)
            ZStack {
                // 0 ライン。
                Path { p in
                    let midY = geo.size.height / 2
                    p.move(to: CGPoint(x: 0, y: midY))
                    p.addLine(to: CGPoint(x: geo.size.width, y: midY))
                }
                .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))

                // 折れ線。
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: first)
                    for pt in points.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(.tint, lineWidth: 2)

                // 各点。
                ForEach(Array(points.enumerated()), id: \.offset) { idx, pt in
                    Circle()
                        .fill(Theme.color(forPhase: cards[idx].phaseNumber))
                        .frame(width: 7, height: 7)
                        .position(pt)
                }
            }
        }
    }

    private func curvePoints(in size: CGSize) -> [CGPoint] {
        guard !cards.isEmpty else { return [] }
        let stepX = size.width / CGFloat(max(1, cards.count - 1))
        return cards.enumerated().map { idx, card in
            let x = CGFloat(idx) * stepX
            let normalized = Theme.normalizedEmotion(card.emotionalValue) // 0...1
            let y = size.height * (1 - CGFloat(normalized))
            return CGPoint(x: x, y: y)
        }
    }
}

#Preview {
    NavigationStack {
        PhaseGridView()
    }
    .environmentForPreview()
}
