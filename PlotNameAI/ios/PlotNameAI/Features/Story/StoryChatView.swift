import SwiftUI

// MARK: - ChatMessage

/// ストーリーチャットの 1 メッセージ。
private struct ChatMessage: Identifiable, Hashable {
    enum Role { case user, assistant, system }
    let id = UUID()
    let role: Role
    let text: String
}

// MARK: - StoryChatView

/// ストーリーの骨子をチャット形式で確認・調整する画面。
/// 入力は SafetyService で検査し、著作権侵害を拒否する。
struct StoryChatView: View {

    @Environment(ProjectStore.self) private var store
    @Environment(SafetyService.self) private var safety

    @State private var input = ""
    @State private var messages: [ChatMessage] = []
    @State private var safetyAlert: String?

    private var brief: StoryBrief? { store.selectedBundle?.brief }

    /// 安全性アラートの表示状態。
    private var showSafetyAlert: Binding<Bool> {
        Binding(
            get: { safetyAlert != nil },
            set: { if !$0 { safetyAlert = nil } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            briefHeader

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            inputBar
        }
        .navigationTitle("ストーリー")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: seedIfNeeded)
        .alert("入力できません", isPresented: showSafetyAlert) {
            Button("OK") { safetyAlert = nil }
        } message: {
            Text(safetyAlert ?? "")
        }
    }

    // MARK: Brief header

    @ViewBuilder
    private var briefHeader: some View {
        if let brief {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Chip(text: brief.saveTheCatType.displayName, color: .indigo)
                    Spacer()
                    Text("テーマ：\(brief.theme)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(brief.logline)
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 2) {
                    Text("主人公：\(brief.protagonist.name)").font(.caption.bold())
                    Text("欲求：\(brief.protagonist.want)").font(.caption2).foregroundStyle(.secondary)
                    Text("必要：\(brief.protagonist.need)").font(.caption2).foregroundStyle(.secondary)
                    Text("欠点：\(brief.protagonist.flaw)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.thinMaterial)
        } else {
            ContentUnavailableView(
                "ブリーフがありません",
                systemImage: "bubble.left",
                description: Text("まず新規プロジェクトでアイデアを生成してください。")
            )
            .frame(maxHeight: 220)
        }
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("調整したい点を入力（例：主人公をもっと弱気に）", text: $input, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
            Button {
                send()
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .accessibilityLabel("送信")
            .buttonStyle(.borderedProminent)
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .background(.bar)
    }

    // MARK: Actions

    private func seedIfNeeded() {
        guard messages.isEmpty else { return }
        if let brief {
            messages = [
                ChatMessage(role: .assistant,
                            text: "「\(brief.logline)」を \(brief.saveTheCatType.displayName) として構成しました。気になる点があれば調整しましょう。")
            ]
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        // 安全性チェック。
        let result = safety.check(text)
        guard result.isAllowed else {
            safetyAlert = result.reason
            input = ""
            return
        }

        messages.append(ChatMessage(role: .user, text: text))
        input = ""

        // Mock の簡易応答（オフライン）。
        let reply = "「\(text)」を反映する方向で調整できます。確定するには各フェーズ画面で内容を編集してください。"
        messages.append(ChatMessage(role: .assistant, text: reply))
    }
}

// MARK: - ChatBubble

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.subheadline)
                .padding(10)
                .background(background, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(message.role == .user ? .white : .primary)
            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    private var background: Color {
        switch message.role {
        case .user: return .accentColor
        case .assistant: return Color(.secondarySystemBackground)
        case .system: return Color(.tertiarySystemBackground)
        }
    }
}

#Preview {
    NavigationStack {
        StoryChatView()
    }
    .environmentForPreview()
}
