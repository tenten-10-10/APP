import SwiftUI

// MARK: - NewProjectView

/// 一行のアイデアから新規プロジェクトを作り、生成パイプラインを起動する。
struct NewProjectView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectStore.self) private var store
    @Environment(GenerationService.self) private var generation
    @Environment(SafetyService.self) private var safety
    @Environment(BillingService.self) private var billing
    @Environment(UsageService.self) private var usage

    @State private var logline = ""
    @State private var title = ""
    @State private var format: Format = .manga
    @State private var pageCount = 35
    @State private var targetReader = "10代〜20代"
    @State private var isGenerating = false

    /// 入力のリアルタイム安全性結果。
    private var safetyResult: SafetyResult {
        safety.check(logline)
    }

    private var canSubmit: Bool {
        !logline.trimmingCharacters(in: .whitespaces).isEmpty
        && safetyResult.isAllowed
        && !isGenerating
    }

    var body: some View {
        Form {
            Section("アイデア（一行）") {
                TextField("例：走るのをやめた少年が、廃部寸前の部のため再び走り出す", text: $logline, axis: .vertical)
                    .lineLimit(2...4)
                if !safetyResult.isAllowed {
                    Label(safetyResult.reason ?? "使用できない語が含まれています。", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("基本設定") {
                TextField("タイトル（任意・空なら自動）", text: $title)
                Picker("フォーマット", selection: $format) {
                    ForEach(Format.allCases) { f in
                        Text(f.displayName).tag(f)
                    }
                }
                Stepper("ページ数: \(pageCount)", value: $pageCount, in: 4...maxPages, step: 1)
                TextField("対象読者", text: $targetReader)
            }

            Section {
                if isGenerating {
                    GenerationProgressInline()
                } else {
                    Button {
                        startGeneration()
                    } label: {
                        Label("ネームを生成", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
                }
            } footer: {
                Text("オフラインの Mock AI が、Save the Cat 分類→13フェーズ→\(pageCount)ページ→コマ→セリフを生成します。")
            }

            if let error = generation.errorMessage {
                Section {
                    Label(error, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("新規プロジェクト")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
                    .disabled(isGenerating)
            }
        }
    }

    /// 現在のプランの最大ページ数。
    private var maxPages: Int {
        max(16, billing.entitlement.limits.maxPagesPerProject)
    }

    private func startGeneration() {
        // クレジット確認（合計 6 クレジット消費する想定）。
        guard usage.canSpend(6) else {
            billing.requireFeature(.basicGeneration)
            generation.errorMessage = "今月のクレジットが不足しています。プランをご確認ください。"
            return
        }

        let project = Project(
            title: title.trimmingCharacters(in: .whitespaces),
            format: format,
            pageCount: pageCount,
            targetReader: targetReader,
            tone: [],
            status: .generating
        )
        let id = store.addProject(project)

        isGenerating = true
        Task {
            await generation.generate(projectID: id, logline: logline, pageCount: pageCount)
            isGenerating = false
            if generation.errorMessage == nil {
                dismiss()
            }
        }
    }
}

// MARK: - GenerationProgressInline

/// 生成中のインライン進捗表示。
struct GenerationProgressInline: View {
    @Environment(GenerationService.self) private var generation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let job = generation.currentJob {
                ProgressView(value: job.progress) {
                    Text(job.stage.displayName)
                        .font(.subheadline.bold())
                }
                Text(job.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("準備中…")
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        NewProjectView()
    }
    .environmentForPreview()
}
