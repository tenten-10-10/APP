import SwiftUI

// MARK: - HomeView

/// プロジェクト一覧。新規作成への入り口。iPhone ではナビゲーションの起点。
struct HomeView: View {

    @Environment(ProjectStore.self) private var store
    @Environment(BillingService.self) private var billing
    @State private var showingNewProject = false

    var body: some View {
        List {
            if store.projects.isEmpty {
                ContentUnavailableView(
                    "プロジェクトがありません",
                    systemImage: "plus.rectangle.on.rectangle",
                    description: Text("右上の＋から、ひとつのアイデアでネームを作りましょう。")
                )
            } else {
                ForEach(store.projects) { project in
                    NavigationLink(value: project.id) {
                        ProjectRow(project: project)
                    }
                }
                .onDelete(perform: deleteProjects)
            }
        }
        .navigationTitle("PlotName AI")
        .navigationDestination(for: UUID.self) { id in
            ProjectDetailRouter(projectID: id)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    handleNewProject()
                } label: {
                    Label("新規", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewProject) {
            NavigationStack {
                NewProjectView()
            }
        }
    }

    private func handleNewProject() {
        // プロジェクト数の上限を確認（同梱サンプルは数えない）。
        if billing.canCreateProject(currentCount: store.userProjectCount) {
            showingNewProject = true
        } else {
            billing.requireFeature(.unlimitedProjects)
        }
    }

    private func deleteProjects(at offsets: IndexSet) {
        let ids = offsets.map { store.projects[$0].id }
        ids.forEach { store.deleteProject($0) }
    }
}

// MARK: - ProjectRow

private struct ProjectRow: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(project.title)
                    .font(.headline)
                Spacer()
                Chip(text: project.status.displayName, color: statusColor)
            }
            HStack(spacing: 8) {
                Chip(text: project.format.displayName, color: .gray)
                Chip(text: "\(project.pageCount)P", color: .gray)
                ForEach(project.tone.prefix(2), id: \.self) { tone in
                    Chip(text: tone, color: .purple)
                }
            }
            Text(project.updatedAt, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch project.status {
        case .draft: return .gray
        case .generating: return .orange
        case .ready: return .green
        case .archived: return .gray
        }
    }
}

// MARK: - ProjectDetailRouter

/// iPhone での詳細ハブ。選択プロジェクトを設定し、各フェーズへ遷移する。
private struct ProjectDetailRouter: View {
    let projectID: UUID
    @Environment(ProjectStore.self) private var store

    var body: some View {
        Group {
            if let bundle = store.bundle(for: projectID) {
                ProjectHubView(bundle: bundle)
            } else {
                ContentUnavailableView("見つかりません", systemImage: "questionmark.folder")
            }
        }
        .onAppear { store.selectedProjectID = projectID }
    }
}

// MARK: - ProjectHubView

/// iPhone: 1プロジェクトの作業メニュー。
private struct ProjectHubView: View {
    let bundle: ProjectBundle
    @State private var selectedPage = 1
    @State private var selectedPanelID: PanelSpec.ID?

    var body: some View {
        List {
            Section("企画") {
                NavigationLink {
                    StoryChatView()
                } label: {
                    Label("ストーリー", systemImage: "bubble.left.and.text.bubble.right")
                }
                NavigationLink {
                    PhaseGridView()
                } label: {
                    Label("13フェーズ", systemImage: "square.grid.3x3")
                }
                NavigationLink {
                    PagePlanView(selectedPage: $selectedPage)
                } label: {
                    Label("ページプラン", systemImage: "doc.on.doc")
                }
            }

            Section("ネーム") {
                NavigationLink {
                    NameCanvasView(
                        bundle: bundle,
                        selectedPage: selectedPage,
                        selectedPanelID: $selectedPanelID
                    )
                } label: {
                    Label("ネームキャンバス", systemImage: "rectangle.split.3x3")
                }
            }

            Section("仕上げ") {
                NavigationLink {
                    ExportView()
                } label: {
                    Label("書き出し", systemImage: "square.and.arrow.up")
                }
                NavigationLink {
                    UsageView()
                } label: {
                    Label("使用状況", systemImage: "chart.bar")
                }
            }
        }
        .navigationTitle(bundle.project.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .environmentForPreview()
}
