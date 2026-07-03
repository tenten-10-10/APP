import SwiftUI
import CoreData

struct ActivityView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings

    // Entity-NAME-based requests (see HomeView): the `sortDescriptors:` convenience
    // form resolves via NSManagedObject.entity(), which returns nil under CloudKit
    // mirroring and crashes SwiftUI with "A fetch request must have an entity."
    @FetchRequest(fetchRequest: {
        let r = InventoryEvent.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \InventoryEvent.occurredAt, ascending: false)]
        return r
    }(), animation: .default) private var events: FetchedResults<InventoryEvent>

    @FetchRequest(fetchRequest: {
        let r = Project.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Project.name, ascending: true)]
        return r
    }()) private var projects: FetchedResults<Project>

    @State private var selectedProjectID: NSManagedObjectID?
    @State private var selectedType: InventoryEventType?
    @State private var period: Period = .all
    @State private var error: PresentableError?

    enum Period: String, CaseIterable, Identifiable {
        case all, today, week, month
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all:   return NSLocalizedString("全期間", comment: "")
            case .today: return NSLocalizedString("今日", comment: "")
            case .week:  return NSLocalizedString("7日間", comment: "")
            case .month: return NSLocalizedString("30日間", comment: "")
            }
        }
        var cutoff: Date? {
            let cal = Calendar.current
            switch self {
            case .all:   return nil
            case .today: return cal.startOfDay(for: Date())
            case .week:  return cal.date(byAdding: .day, value: -7, to: Date())
            case .month: return cal.date(byAdding: .day, value: -30, to: Date())
            }
        }
    }

    private var filtered: [InventoryEvent] {
        events.filter { event in
            if let pid = selectedProjectID, event.project?.objectID != pid { return false }
            if let type = selectedType, event.eventType != type { return false }
            if let cutoff = period.cutoff, (event.occurredAt ?? .distantPast) < cutoff { return false }
            return true
        }
    }

    var body: some View {
        List {
            Section {
                Picker(NSLocalizedString("プロジェクト", comment: ""), selection: $selectedProjectID) {
                    Text(NSLocalizedString("すべて", comment: "")).tag(NSManagedObjectID?.none)
                    ForEach(projects) { Text($0.displayName).tag(Optional($0.objectID)) }
                }
                Picker(NSLocalizedString("種別", comment: ""), selection: $selectedType) {
                    Text(NSLocalizedString("すべて", comment: "")).tag(InventoryEventType?.none)
                    ForEach(InventoryEventType.allCases) { Text($0.localizedTitle).tag(Optional($0)) }
                }
                Picker(NSLocalizedString("期間", comment: ""), selection: $period) {
                    ForEach(Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            EventListView(events: Array(filtered.prefix(300)), onCorrect: correct)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("活動", comment: ""))
        .errorAlert($error)
    }

    private func correct(_ event: InventoryEvent) {
        let eventID = event.objectID
        let actor = settings.effectiveOperatorName
        // Respect read-only projects.
        if let project = event.project, !container.sharing.canEdit(project) {
            error = PresentableError(AppError.readOnlyProject); return
        }
        let result = container.performWrite { ctx in
            guard let original = try ctx.existingObject(with: eventID) as? InventoryEvent else { return }
            container.inventory.reverse(event: original, actor: actor,
                                        note: NSLocalizedString("活動画面からの訂正", comment: ""), in: ctx)
        }
        if case .failure(let err) = result { error = PresentableError(err) }
    }
}
