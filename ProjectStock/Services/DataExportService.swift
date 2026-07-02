import Foundation
import CoreData

/// JSON export of the inventory data for backup / portability (spec §12.7,
/// §16: written to a temp file, gated by a confirmation in the UI).
struct DataExportService {

    struct ExportRoot: Codable {
        let app = "ProjectStock"
        let exportedAt: Date
        let projects: [ProjectDTO]
    }
    struct ProjectDTO: Codable {
        let id: String
        let name: String
        let note: String
        let products: [ProductDTO]
        let locations: [LocationDTO]
        let events: [EventDTO]
    }
    struct ProductDTO: Codable {
        let id: String
        let name: String
        let sku: String
        let unit: String
        let trackingMode: String
        let currentQuantity: Double
        let minimumStock: Double
    }
    struct LocationDTO: Codable {
        let id: String
        let name: String
        let kind: String
        let path: String
    }
    struct EventDTO: Codable {
        let id: String
        let type: String
        let quantityDelta: Double
        let occurredAt: Date
        let actor: String
        let product: String?
        let note: String
    }

    func exportJSON(context: NSManagedObjectContext, exportedAt: Date = Date()) throws -> URL {
        let request: NSFetchRequest<Project> = Project.fetchRequest()
        let projects = try context.fetch(request)
        let dtos = projects.map { project in
            ProjectDTO(id: project.id?.uuidString ?? "",
                       name: project.displayName,
                       note: project.note ?? "",
                       products: project.productArray.map { p in
                           ProductDTO(id: p.id?.uuidString ?? "", name: p.displayName, sku: p.sku ?? "",
                                      unit: p.unitLabel, trackingMode: p.trackingMode.rawValue,
                                      currentQuantity: p.currentQuantity, minimumStock: p.minimumStock)
                       },
                       locations: project.locationArray.map { l in
                           LocationDTO(id: l.id?.uuidString ?? "", name: l.displayName, kind: l.kind.rawValue, path: l.breadcrumb)
                       },
                       events: project.eventArray.map { e in
                           EventDTO(id: e.id?.uuidString ?? "", type: e.eventType.rawValue, quantityDelta: e.quantityDelta,
                                    occurredAt: e.occurredAt ?? Date(), actor: e.actorName, product: e.product?.displayName, note: e.note ?? "")
                       })
        }
        let root = ExportRoot(exportedAt: exportedAt, projects: dtos)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(root)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(NSLocalizedString("タナミル_データ書き出し", comment: ""))_\(QRExportService.dateStamp()).json"
        let url = dir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
