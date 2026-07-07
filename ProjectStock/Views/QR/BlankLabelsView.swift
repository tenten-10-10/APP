import SwiftUI
import CoreData

/// Every blank (issued but unassigned) QR in a project. Before this screen,
/// over-printed codes piled up invisibly with no way to review or retire
/// them. Codes are never physically deleted (spec §6: uniqueness / history),
/// but retiring makes a lost sheet scan as 「無効」 instead of as a live
/// blank someone could mis-assign.
struct BlankLabelsView: View {
    @EnvironmentObject private var container: ServiceContainer
    @ObservedObject var project: Project

    @State private var retiring: CodeAlias?
    @State private var error: PresentableError?

    private var blanks: [CodeAlias] {
        project.labelArray
            .filter { $0.isActive && $0.targetType == .unassigned }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    private var canEdit: Bool { container.sharing.canEdit(project) }

    var body: some View {
        List {
            Section {
                if blanks.isEmpty {
                    Text(NSLocalizedString("未割当の空きQRはありません。「空のQRをまとめて発行」で作成できます。", comment: ""))
                        .font(.footnote).foregroundColor(.secondary)
                }
                ForEach(blanks) { alias in
                    NavigationLink(destination: QRLabelStudioView(code: alias.code,
                                                                  projectName: project.displayName,
                                                                  targetName: NSLocalizedString("未割当", comment: ""))) {
                        HStack {
                            Image(systemName: "qrcode")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alias.code).font(.system(.callout, design: .monospaced))
                                HStack(spacing: 6) {
                                    if let created = alias.createdAt {
                                        Text(String(format: NSLocalizedString("発行: %@", comment: ""),
                                                    DateFormatters.day.string(from: created)))
                                    }
                                    if alias.scanCount > 0 {
                                        Text(String(format: NSLocalizedString("スキャン %d 回", comment: ""), alias.scanCount))
                                    }
                                }
                                .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if canEdit {
                            Button(role: .destructive) { retiring = alias } label: {
                                Label(NSLocalizedString("無効化", comment: ""), systemImage: "nosign")
                            }
                        }
                    }
                }
            } header: {
                Text(String(format: NSLocalizedString("未割当 %d 件", comment: ""), blanks.count))
            } footer: {
                Text(NSLocalizedString("発行したが使わない・紛失したQRは、左スワイプで無効化できます。無効化したQRは読み取っても「無効」と案内されるだけで、誤って登録されることがなくなります。", comment: ""))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("空のQR一覧", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .alert(NSLocalizedString("QRを無効化しますか？", comment: ""),
               isPresented: Binding(get: { retiring != nil },
                                    set: { if !$0 { retiring = nil } }),
               presenting: retiring) { alias in
            Button(NSLocalizedString("無効化する", comment: ""), role: .destructive) {
                retire(alias); retiring = nil
            }
            Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) { retiring = nil }
        } message: { alias in
            Text(String(format: NSLocalizedString("%@ は読み取っても使えなくなります（元に戻せません）。", comment: ""), alias.code))
        }
        .errorAlert($error)
    }

    private func retire(_ alias: CodeAlias) {
        let aliasID = alias.objectID
        let result = container.performWrite { ctx in
            guard let a = try ctx.existingObject(with: aliasID) as? CodeAlias else { return }
            container.aliases.retire(alias: a)
        }
        if case .failure(let err) = result { error = PresentableError(err) } else { Haptics.success() }
    }
}
