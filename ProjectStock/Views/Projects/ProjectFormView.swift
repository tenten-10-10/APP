import SwiftUI

/// Create or edit a project (spec §12.2). Read-only projects never reach the
/// edit path because the caller hides the entry point.
struct ProjectFormView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var project: Project?
    /// Called with the freshly created project so the caller can navigate
    /// straight into it (only fired on create, not edit).
    var onCreated: ((Project) -> Void)? = nil

    @State private var name: String = ""
    @State private var note: String = ""
    @State private var color: ProjectColor = .blue
    @State private var defaultMode: TrackingMode = .quantity
    @State private var error: PresentableError?

    private var isEditing: Bool { project != nil }

    var body: some View {
        NavigationView {
            Form {
                Section(NSLocalizedString("基本情報", comment: "")) {
                    TextField(NSLocalizedString("プロジェクト名", comment: ""), text: $name)
                        .accessibilityIdentifier("projectNameField")
                }
                Section(NSLocalizedString("メモ", comment: "")) {
                    MultilineTextField(text: $note,
                                       placeholder: NSLocalizedString("メモ（任意）", comment: ""))
                        .frame(minHeight: 80)
                }
                Section(NSLocalizedString("色", comment: "")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(ProjectColor.allCases) { option in
                            Circle()
                                .fill(option.color)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(Color.primary, lineWidth: color == option ? 3 : 0))
                                .onTapGesture { color = option }
                                .accessibilityLabel(Text(option.localizedTitle))
                                .accessibilityAddTraits(color == option ? [.isSelected] : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                if !isEditing {
                    Section {
                        ForEach(TrackingMode.allCases) { mode in
                            Button { defaultMode = mode } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: mode.systemImageName)
                                        .font(.title3).frame(width: 28)
                                        .foregroundColor(defaultMode == mode ? Brand.primary : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.localizedTitle).foregroundColor(.primary)
                                        Text(mode.explanation).font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: defaultMode == mode ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(defaultMode == mode ? Brand.primary : Color(.tertiaryLabel))
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("projectMode_\(mode.rawValue)")
                            .accessibilityAddTraits(defaultMode == mode ? [.isSelected] : [])
                        }
                    } header: {
                        Text(NSLocalizedString("主に扱うもの", comment: ""))
                    } footer: {
                        Text(NSLocalizedString("新しい製品の初期値になります。製品ごとにあとで変更できます。", comment: ""))
                    }
                }
            }
            .navigationTitle(isEditing ? NSLocalizedString("プロジェクトを編集", comment: "") : NSLocalizedString("新規プロジェクト", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("キャンセル", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("保存", comment: "")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("saveProjectButton")
                }
            }
            .onAppear(perform: loadIfEditing)
            .errorAlert($error)
        }
    }

    private func loadIfEditing() {
        guard let project else { return }
        name = project.displayName
        note = project.note ?? ""
        color = project.color
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note
        let chosen = color
        let mode = defaultMode
        let owner = settings.effectiveOperatorName
        let editingID = project?.objectID

        var createdID: NSManagedObjectID?
        let result = container.performWrite { ctx in
            if let editingID, let existing = try? ctx.existingObject(with: editingID) as? Project {
                existing.name = trimmedName
                existing.note = trimmedNote
                existing.color = chosen
                existing.touch()
            } else {
                let created = container.projects.createProject(name: trimmedName, ownerDisplayName: owner,
                                                               color: chosen, defaultMode: mode, in: ctx)
                created.note = trimmedNote
                try ctx.obtainPermanentIDs(for: [created])
                createdID = created.objectID
            }
        }
        switch result {
        case .success:
            dismiss()
            if let createdID, let onCreated,
               let proj = try? container.viewContext.existingObject(with: createdID) as? Project {
                onCreated(proj)
            }
        case .failure(let err): error = PresentableError(err)
        }
    }
}
