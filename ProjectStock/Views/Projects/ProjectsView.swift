import SwiftUI
import CoreData

struct ProjectsView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var syncMonitor: CloudKitSyncMonitor

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Project.updatedAt, ascending: false)],
        animation: .default
    ) private var projects: FetchedResults<Project>

    @State private var searchText = ""
    @State private var showArchived = false
    @State private var showingCreate = false
    @State private var error: PresentableError?

    private var filtered: [Project] {
        projects.filter { project in
            (showArchived || !project.isArchived) &&
            (searchText.isEmpty || project.displayName.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(filtered) { project in
                    NavigationLink(destination: ProjectDetailView(project: project)) {
                        ProjectRow(project: project)
                    }
                }
            } footer: {
                if filtered.isEmpty {
                    EmptyStateView(systemImage: "folder.badge.plus",
                                   title: NSLocalizedString("プロジェクトがありません", comment: ""),
                                   message: NSLocalizedString("右上の＋で作成するか、サンプルを生成してください。", comment: ""))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("プロジェクト", comment: ""))
        .searchable(text: $searchText, prompt: NSLocalizedString("名称で検索", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                SyncStatusBadge(state: syncMonitor.syncState)
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Toggle(isOn: $showArchived) {
                        Label(NSLocalizedString("アーカイブを表示", comment: ""), systemImage: "archivebox")
                    }
                    Button {
                        createSample()
                    } label: {
                        Label(NSLocalizedString("サンプルを生成", comment: ""), systemImage: "wand.and.stars")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("createProjectButton")
            }
        }
        .sheet(isPresented: $showingCreate) {
            ProjectFormView()
        }
        .errorAlert($error)
    }

    private func createSample() {
        let result = container.performWrite { ctx in
            _ = try container.sampleData.makeSampleProject(in: ctx, owner: settings.effectiveOperatorName)
        }
        if case .failure(let err) = result { error = PresentableError(err) }
    }
}

private struct ProjectRow: View {
    @EnvironmentObject private var container: ServiceContainer
    @ObservedObject var project: Project

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(project.color.color)
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(project.displayName).font(.headline).lineLimit(1)
                    if project.isSample {
                        Text(NSLocalizedString("サンプル", comment: ""))
                            .font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color(.tertiarySystemFill)))
                    }
                }
                HStack(spacing: 8) {
                    Label("\(project.activeProductCount)", systemImage: "shippingbox")
                        .font(.caption).foregroundColor(.secondary)
                    if project.lowStockCount > 0 { LowStockChip() }
                    if container.router.isShared(project) {
                        Image(systemName: "person.2.fill").font(.caption2).foregroundColor(.secondary)
                            .accessibilityLabel(Text(NSLocalizedString("共有プロジェクト", comment: "")))
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
