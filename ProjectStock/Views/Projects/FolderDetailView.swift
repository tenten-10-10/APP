import SwiftUI
import CoreData

/// The inside of a folder — before this, folder rows were dead ends: no way
/// to see, rename, or dissolve what you'd filed. Products link through to
/// their detail; rename / delete live in the toolbar.
struct FolderDetailView: View {
    @EnvironmentObject private var container: ServiceContainer
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var folder: Folder
    let canEdit: Bool

    @State private var renaming = false
    @State private var confirmingDelete = false
    @State private var error: PresentableError?

    private var products: [Product] {
        folder.productArray.filter { !$0.isArchived }
    }

    var body: some View {
        List {
            if !folder.childArray.isEmpty {
                Section(NSLocalizedString("サブフォルダ", comment: "")) {
                    ForEach(folder.childArray) { child in
                        NavigationLink(destination: FolderDetailView(folder: child, canEdit: canEdit)) {
                            HStack {
                                Label(child.displayName, systemImage: "folder")
                                Spacer()
                                Text("\(child.productArray.count)").foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            Section {
                if products.isEmpty {
                    Text(NSLocalizedString("このフォルダに製品はありません", comment: "")).foregroundColor(.secondary)
                }
                ForEach(products) { product in
                    NavigationLink(destination: ProductDetailView(product: product)) {
                        ProductRow(product: product)
                    }
                }
            } header: {
                Text(NSLocalizedString("製品", comment: ""))
            } footer: {
                Text(NSLocalizedString("製品のフォルダは、製品の編集画面（製品を開いて鉛筆ボタン）で変更できます。", comment: ""))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(folder.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // iOS 15: `if` はToolbarContentBuilder直下に置けないため item 内で分岐
            ToolbarItem(placement: .navigationBarTrailing) {
                if canEdit {
                    Menu {
                        Button { renaming = true } label: {
                            Label(NSLocalizedString("名前を変更", comment: ""), systemImage: "pencil")
                        }
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Label(NSLocalizedString("フォルダを削除", comment: ""), systemImage: "trash")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel(Text(NSLocalizedString("その他の操作", comment: "")))
                }
            }
        }
        .sheet(isPresented: $renaming) {
            RenameSheet(title: NSLocalizedString("フォルダ名を変更", comment: ""),
                        placeholder: NSLocalizedString("フォルダ名", comment: ""),
                        initialText: folder.displayName) { newName in
                rename(to: newName)
            }
        }
        .alert(NSLocalizedString("フォルダを削除しますか？", comment: ""), isPresented: $confirmingDelete) {
            Button(NSLocalizedString("削除", comment: ""), role: .destructive) { deleteFolder() }
            Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) {}
        } message: {
            Text(String(format: NSLocalizedString("フォルダ「%@」を削除します。中の製品は削除されず「フォルダなし」になります（サブフォルダも削除されます）。", comment: ""), folder.displayName))
        }
        .errorAlert($error)
    }

    private func rename(to newName: String) {
        let folderID = folder.objectID
        let result = container.performWrite { ctx in
            guard let f = try ctx.existingObject(with: folderID) as? Folder else { return }
            f.name = newName
            f.touch()
        }
        if case .failure(let err) = result { error = PresentableError(err) } else { Haptics.success() }
    }

    private func deleteFolder() {
        let folderID = folder.objectID
        let result = container.performWrite { ctx in
            guard let f = try ctx.existingObject(with: folderID) as? Folder else { return }
            ctx.delete(f)
        }
        switch result {
        case .success: Haptics.success(); dismiss()
        case .failure(let err): error = PresentableError(err)
        }
    }
}
