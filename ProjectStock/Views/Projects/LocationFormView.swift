import CoreData
import SwiftUI

/// Create / edit a `Location` with a parent picker that rejects cycles
/// (validation happens in `LocationService`, spec §5.5).
struct LocationFormView: View {
    @EnvironmentObject private var container: ServiceContainer
    @Environment(\.dismiss) private var dismiss

    let project: Project
    var editing: Location?
    var defaultParent: Location?

    @State private var name = ""
    @State private var kind: LocationKind = .container
    @State private var parentID: NSManagedObjectID?
    @State private var note = ""
    @State private var error: PresentableError?

    var body: some View {
        NavigationView {
            Form {
                Section(NSLocalizedString("基本情報", comment: "")) {
                    TextField(NSLocalizedString("場所名", comment: ""), text: $name)
                        .accessibilityIdentifier("locationNameField")
                    Picker(NSLocalizedString("種類", comment: ""), selection: $kind) {
                        ForEach(LocationKind.allCases) { Text($0.localizedTitle).tag($0) }
                    }
                }
                Section(NSLocalizedString("親の場所", comment: "")) {
                    Picker(NSLocalizedString("親", comment: ""), selection: $parentID) {
                        Text(NSLocalizedString("なし（最上位）", comment: "")).tag(NSManagedObjectID?.none)
                        ForEach(candidateParents) { loc in
                            Text(loc.breadcrumb).tag(Optional(loc.objectID))
                        }
                    }
                }
                Section(NSLocalizedString("メモ", comment: "")) {
                    MultilineTextField(text: $note, placeholder: NSLocalizedString("メモ（任意）", comment: ""))
                        .frame(minHeight: 60)
                }
            }
            .navigationTitle(editing == nil ? NSLocalizedString("新規の場所", comment: "") : NSLocalizedString("場所を編集", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(NSLocalizedString("キャンセル", comment: "")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("保存", comment: "")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
            .errorAlert($error)
        }
    }

    private var candidateParents: [Location] {
        // Exclude self and descendants to keep the picker cycle-free.
        project.locationArray.filter { candidate in
            guard let editing else { return true }
            if candidate.objectID == editing.objectID { return false }
            var node: Location? = candidate
            var guardCount = 0
            while let n = node, guardCount < 4096 {
                if n.objectID == editing.objectID { return false }
                node = n.parent; guardCount += 1
            }
            return true
        }
    }

    private func load() {
        if let editing {
            name = editing.displayName
            kind = editing.kind
            parentID = editing.parent?.objectID
            note = editing.note ?? ""
        } else if let defaultParent {
            parentID = defaultParent.objectID
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenKind = kind
        let chosenParent = parentID
        let chosenNote = note
        let projectID = project.objectID
        let editingID = editing?.objectID

        // Block a same-name sibling (same parent) so we never end up with two
        // indistinguishable locations at the same level.
        let isDuplicate = project.locationArray.contains {
            $0.objectID != editingID
                && $0.parent?.objectID == chosenParent
                && $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        if isDuplicate {
            error = PresentableError(AppError.underlying(String(format: NSLocalizedString("同じ場所の中に「%@」という名前の場所は既にあります。", comment: ""), trimmed)))
            return
        }

        let result = container.performWrite { ctx in
            guard let p = try ctx.existingObject(with: projectID) as? Project else { return }
            let parent = chosenParent.flatMap { try? ctx.existingObject(with: $0) as? Location }
            let location: Location
            if let editingID, let existing = try? ctx.existingObject(with: editingID) as? Location {
                location = existing
                location.name = trimmed
                location.kind = chosenKind
                location.note = chosenNote
                location.touch()
            } else {
                location = Location.make(in: ctx, name: trimmed, project: p, kind: chosenKind)
                location.note = chosenNote
                container.router.assignChild(location, toSameStoreAs: p, in: ctx)
            }
            try container.locations.setParent(location, to: parent)
        }
        switch result {
        case .success: dismiss()
        case .failure(let err): error = PresentableError(err)
        }
    }
}
