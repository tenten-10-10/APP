import SwiftUI

/// One ledger row (spec §4.4, §12.6).
struct EventRow: View {
    @ObservedObject var event: InventoryEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.eventType.systemImageName)
                .foregroundColor(.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(event.eventType.localizedTitle).font(.subheadline).bold()
                    if event.isCorrection {
                        Text(NSLocalizedString("訂正", comment: ""))
                            .font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                            .foregroundColor(.orange)
                    }
                    Spacer()
                    if event.eventType.affectsQuantityTotal && event.quantityDelta != 0 {
                        Text(deltaString)
                            .font(.subheadline).monospacedDigit()
                            .foregroundColor(event.quantityDelta >= 0 ? .green : .red)
                    }
                }
                if let target = targetName {
                    Text(target).font(.caption).foregroundColor(.primary).lineLimit(1)
                }
                if let route = routeString {
                    Text(route).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(event.actorName)
                    Text("·")
                    Text(timeString)
                }
                .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var deltaString: String {
        let v = event.quantityDelta
        return (v >= 0 ? "+" : "") + v.quantityString
    }
    private var targetName: String? {
        if let p = event.product { return p.displayName }
        if let u = event.unit { return u.displaySerial }
        return nil
    }
    private var routeString: String? {
        switch (event.sourceLocation, event.destinationLocation) {
        case let (src?, dst?): return "\(src.displayName) → \(dst.displayName)"
        case let (nil, dst?):  return "→ \(dst.displayName)"
        case let (src?, nil):  return "\(src.displayName) →"
        default: return nil
        }
    }
    private var timeString: String {
        guard let date = event.occurredAt else { return "" }
        return DateFormatters.short.string(from: date)
    }
}

/// A grouped-by-day list of events with optional correction support.
struct EventListView: View {
    let events: [InventoryEvent]
    var onCorrect: ((InventoryEvent) -> Void)? = nil

    /// One day's worth of events. A named `Identifiable` type is used instead
    /// of a tuple because Swift key paths cannot index tuple elements.
    private struct DayGroup: Identifiable {
        let day: Date
        let items: [InventoryEvent]
        var id: Date { day }
    }

    private var grouped: [DayGroup] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.occurredAt ?? Date())
        }
        return groups.keys.sorted(by: >).map { day in
            DayGroup(day: day, items: groups[day]!.sorted { ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast) })
        }
    }

    var body: some View {
        if events.isEmpty {
            EmptyStateView(systemImage: "clock", title: NSLocalizedString("活動がありません", comment: ""))
        } else {
            ForEach(grouped) { group in
                Section(DateFormatters.day.string(from: group.day)) {
                    ForEach(group.items) { event in
                        EventRow(event: event)
                            .swipeActions(edge: .trailing) {
                                if let onCorrect, !event.isCorrection {
                                    Button {
                                        onCorrect(event)
                                    } label: {
                                        Label(NSLocalizedString("訂正", comment: ""), systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.orange)
                                }
                            }
                    }
                }
            }
        }
    }
}

enum DateFormatters {
    static let short: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
