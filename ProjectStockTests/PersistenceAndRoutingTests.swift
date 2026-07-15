import XCTest
import CoreData
@testable import ProjectStock

final class PersistenceAndRoutingTests: XCTestCase {

    func testNewProjectAndChildrenShareSameStore() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = container.projects.createProject(name: "P", ownerDisplayName: "t", in: ctx)
        let product = Product.make(in: ctx, name: "X", project: project)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        try ctx.save()

        let projectStore = project.objectID.persistentStore
        let productStore = product.objectID.persistentStore
        XCTAssertNotNil(projectStore)
        XCTAssertTrue(projectStore === productStore, "子はProjectと同じStoreに割り当てられる")
        XCTAssertTrue(projectStore === container.persistence.privateStore, "所有プロジェクトはPrivate Store")
    }

    func testCrossProjectAliasAssignmentRejected() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let projectA = container.projects.createProject(name: "A", ownerDisplayName: "t", in: ctx)
        let projectB = container.projects.createProject(name: "B", ownerDisplayName: "t", in: ctx)
        try ctx.save()

        let alias = try container.aliases.createUnassignedBatch(count: 1, in: projectA, context: ctx).first!
        let productB = Product.make(in: ctx, name: "別プロジェクトの製品", project: projectB)
        container.router.assignChild(productB, toSameStoreAs: projectB, in: ctx)
        try ctx.save()

        XCTAssertThrowsError(try container.aliases.assign(alias: alias, to: .product(productB))) { error in
            guard case AppError.crossProjectReference = error else {
                return XCTFail("プロジェクト境界違反を拒否すべき: \(error)")
            }
        }
    }

    func testShareReadinessPassesForCleanProject() throws {
        let container = TestSupport.makeContainer()
        let ctx = container.viewContext
        let project = container.projects.createProject(name: "P", ownerDisplayName: "t", in: ctx)
        let product = Product.make(in: ctx, name: "X", project: project)
        container.router.assignChild(product, toSameStoreAs: project, in: ctx)
        try ctx.save()
        XCTAssertNoThrow(try container.projects.validateShareReadiness(project))
    }

    func testReadOnlyPermissionBlocksEditing() {
        XCTAssertFalse(SharePermission.readOnly.canEdit)
        XCTAssertTrue(SharePermission.readWrite.canEdit)
        XCTAssertTrue(SharePermission.owner.canEdit)
        XCTAssertTrue(SharePermission.notShared.canEdit)
    }
}
