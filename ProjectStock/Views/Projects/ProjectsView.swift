import SwiftUI
import CoreData

struct ProjectsView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var syncMonitor: CloudKitSyncMonitor

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "isPinned", ascending: false),
            NSSortDescriptor(key: "sortIndex", ascending: true),
            NSSortDescriptor(keyPath: \Project.updatedAt, ascending: false)
        ],
        animation: .default
    ) private var projects: FetchedResults<Project>

    @State private var searchText = ""
    @State private var showArchived = false
    @State private var showingCreate = false
    @State private var createdProject: Project?
    @State private var editingProject: Project?
    @State private var deletingProject: Project?
    @State private var infoAlert: String?
    @State private var error: PresentableError?

    private var filtered: [Project] {
        projects.filter { project in
            (showArchived || !project.isArchived) &&
            (searchText.isEmpty || project.displayName.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        content
            .navigationTitle(NSLocalizedString("プロジェクト", comment: ""))
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingCreate) {
                ProjectFormView(onCreated: { createdProject = $0 })
            }
            .sheet(item: $editingProject) { project in
                ProjectFormView(project: project)
            }
            .background(newProjectLink)
            .confirmationDialog(
                NSLocalizedString("このプロジェクトを削除しますか?", comment: ""),
                isPresented: Binding(get: { deletingProject != nil }, set: { if !$0 { deletingProject = nil } }),
                presenting: deletingProject
            ) { project in
                Button(NSLocalizedString("削除", comment: ""), role: .destructive) { delete(project) }
                Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) {}
            } message: { project in
                Text(String(format: NSLocalizedString("「%@」と、その中の製品・履歴がすべて削除されます。", comment: ""), project.displayName))
            }
            .alert(infoAlert ?? "", isPresented: Binding(get: { infoAlert != nil },
                                                         set: { if !$0 { infoAlert = nil } })) {
                Button(NSLocalizedString("OK", comment: "")) { infoAlert = nil }
            }
            .errorAlert($error)
    }

    /// Hidden link that pushes the just-created project so the user lands
    /// straight inside it, ready to add the first product.
    @ViewBuilder private var newProjectLink: some View {
        NavigationLink(
            isActive: Binding(get: { createdProject != nil },
                              set: { if !$0 { createdProject = nil } })
        ) {
            if let createdProject { ProjectDetailView(project: createdProject) }
        } label: { EmptyView() }
        .opacity(0)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        if projects.isEmpty {
            hero
        } else {
            projectList
        }
    }

    private var projectList: some View {
        List {
            Section {
                ForEach(filtered) { project in
                    NavigationLink(destination: ProjectDetailView(project: project)) {
                        ProjectRow(project: project)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { deletingProject = project } label: {
                            Label(NSLocalizedString("削除", comment: ""), systemImage: "trash")
                        }
                        Button { setArchived(project, !project.isArchived) } label: {
                            Label(project.isArchived ? NSLocalizedString("解除", comment: "") : NSLocalizedString("アーカイブ", comment: ""),
                                  systemImage: "archivebox")
                        }.tint(.gray)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button { togglePin(project) } label: {
                            Label(project.isPinned ? NSLocalizedString("ピン解除", comment: "") : NSLocalizedString("ピン留め", comment: ""),
                                  systemImage: project.isPinned ? "pin.slash" : "pin")
                        }.tint(.orange)
                        Button { duplicate(project) } label: {
                            Label(NSLocalizedString("複製", comment: ""), systemImage: "plus.square.on.square")
                        }.tint(.blue)
                    }
                    .contextMenu {
                        Button { editingProject = project } label: {
                            Label(NSLocalizedString("編集", comment: ""), systemImage: "pencil")
                        }
                        Button { togglePin(project) } label: {
                            Label(project.isPinned ? NSLocalizedString("ピン解除", comment: "") : NSLocalizedString("ピン留め", comment: ""),
                                  systemImage: project.isPinned ? "pin.slash" : "pin")
                        }
                        Button { duplicate(project) } label: {
                            Label(NSLocalizedString("複製", comment: ""), systemImage: "plus.square.on.square")
                        }
                        Button { setArchived(project, !project.isArchived) } label: {
                            Label(project.isArchived ? NSLocalizedString("アーカイブ解除", comment: "") : NSLocalizedString("アーカイブ", comment: ""),
                                  systemImage: "archivebox")
                        }
                        Divider()
                        Button(role: .destructive) { deletingProject = project } label: {
                            Label(NSLocalizedString("削除", comment: ""), systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: moveProjects)
            } footer: {
                if filtered.isEmpty {
                    EmptyStateView(systemImage: "magnifyingglass",
                                   title: NSLocalizedString("該当するプロジェクトがありません", comment: ""),
                                   message: NSLocalizedString("検索条件を変えるか、アーカイブの表示を切り替えてください。", comment: ""))
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: NSLocalizedString("名称で検索", comment: ""))
    }

    /// First-launch hero shown when there are no projects at all.
    private var hero: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Brand.gradient)
                    .frame(width: 128, height: 128)
                    .shadow(color: Brand.primary.opacity(0.35), radius: 16, y: 8)
                Image(systemName: "folder.fill.badge.plus")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundColor(.white)
            }
            .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text(NSLocalizedString("最初のプロジェクトを作成", comment: ""))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(NSLocalizedString("在庫を整理するプロジェクトを作成するか、サンプルで使い方を試してみましょう。", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 12) {
                Button {
                    showingCreate = true
                } label: {
                    Label(NSLocalizedString("プロジェクトを作成", comment: ""), systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("heroCreateProjectButton")

                Button {
                    createSample()
                } label: {
                    Label(NSLocalizedString("サンプルを生成", comment: ""), systemImage: "wand.and.stars")
                }
                .font(.subheadline.weight(.medium))
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
            ToolbarItem(placement: .navigationBarLeading) {
                SyncStatusBadge(state: syncMonitor.syncState)
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                EditButton()
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

    private func createSample() {
        if projects.contains(where: { $0.isSample }) {
            infoAlert = NSLocalizedString("サンプルデータは既に作成済みです", comment: ""); return
        }
        let result = container.performWrite { ctx in
            _ = try container.sampleData.makeSampleProject(in: ctx, owner: settings.effectiveOperatorName)
        }
        switch result {
        case .success: infoAlert = NSLocalizedString("サンプルデータを作成しました", comment: "")
        case .failure(let err): error = PresentableError(err)
        }
    }

    // MARK: - Row actions

    private func togglePin(_ project: Project) {
        let id = project.objectID
        _ = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: id) as? Project else { return }
            p.isPinned.toggle(); p.touch()
        }
    }

    private func setArchived(_ project: Project, _ archived: Bool) {
        let id = project.objectID
        _ = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: id) as? Project else { return }
            if archived { container.projects.archive(p) } else { container.projects.unarchive(p) }
        }
    }

    private func duplicate(_ project: Project) {
        let id = project.objectID
        let owner = settings.effectiveOperatorName
        let result = container.performWrite { ctx in
            guard let src = try ctx.existingObject(with: id) as? Project else { return }
            let newName = String(format: NSLocalizedString("%@ のコピー", comment: ""), src.displayName)
            _ = container.projects.duplicate(src, newName: newName, ownerDisplayName: owner, in: ctx)
        }
        switch result {
        case .success: infoAlert = NSLocalizedString("プロジェクトを複製しました", comment: "")
        case .failure(let err): error = PresentableError(err)
        }
    }

    private func delete(_ project: Project) {
        let id = project.objectID
        _ = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: id) as? Project else { return }
            ctx.delete(p)
        }
    }

    /// Reassign sortIndex to the visible order after a drag-reorder.
    private func moveProjects(from source: IndexSet, to destination: Int) {
        var items = filtered
        items.move(fromOffsets: source, toOffset: destination)
        let ids = items.map { $0.objectID }
        _ = container.performWrite { ctx in
            for (i, oid) in ids.enumerated() {
                if let p = try? ctx.existingObject(with: oid) as? Project { p.sortIndex = Int64(i) }
            }
        }
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
                    if project.isPinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundColor(.orange)
                            .accessibilityLabel(Text(NSLocalizedString("ピン留め", comment: "")))
                    }
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
