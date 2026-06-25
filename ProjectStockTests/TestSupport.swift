import XCTest
import CoreData
@testable import ProjectStock

/// Shared helpers for the unit tests. Every test runs against an isolated
/// in-memory two-store stack with CloudKit disabled.
enum TestSupport {

    static func makeContainer() -> ServiceContainer {
        let persistence = PersistenceController(inMemory: true)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        return ServiceContainer(persistence: persistence, device: .shared, settings: settings)
    }

    static func makeProject(_ container: ServiceContainer, name: String = "Test") -> Project {
        let ctx = container.viewContext
        let project = container.projects.createProject(name: name, ownerDisplayName: "tester", in: ctx)
        try? ctx.save()
        return project
    }
}

/// Deterministic random bytes for exercising the regeneration logic in
/// `PublicCodeGenerator` (spec §17).
final class ScriptedRandomProvider: RandomByteProviding {
    private var scripts: [[UInt8]]
    private(set) var callCount = 0
    init(_ scripts: [[UInt8]]) { self.scripts = scripts }
    func randomBytes(count: Int) -> [UInt8] {
        defer { callCount += 1 }
        let index = min(callCount, scripts.count - 1)
        var bytes = scripts[index]
        if bytes.count < count { bytes += [UInt8](repeating: 0, count: count - bytes.count) }
        return Array(bytes.prefix(count))
    }
}
