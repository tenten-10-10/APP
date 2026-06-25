import SwiftUI

/// Create or edit a project (spec §12.2). Read-only projects never reach the
/// edit path because the caller hides the entry point.
struct ProjectFormView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var project: Project?

    @State private var name: String = ""
    @State private var note: String = ""
    @State private var color: ProjectColor = .blue
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
        let owner = settings.effectiveOperatorName
        let editingID = project?.objectID

        let result = container.performWrite { ctx in
            if let editingID, let existing = try? ctx.existingObject(with: editingID) as? Project {
                existing.name = trimmedName
                existing.note = trimmedNote
                existing.color = chosen
                existing.touch()
            } else {
                let created = container.projects.createProject(name: trimmedName, ownerDisplayName: owner,
                                                               color: chosen, in: ctx)
                created.note = trimmedNote
            }
        }
        switch result {
        case .success: dismiss()
        case .failure(let err): error = PresentableError(err)
        }
    }
}
