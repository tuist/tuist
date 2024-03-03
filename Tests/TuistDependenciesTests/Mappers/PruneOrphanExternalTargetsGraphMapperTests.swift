import Foundation
import TSCBasic
import TuistGraph
import TuistGraphTesting
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class PruneOrphanExternalTargetsGraphMapperTests: TuistUnitTestCase {
    var subject: PruneOrphanExternalTargetsGraphMapper!

    override func setUp() {
        super.setUp()
        subject = PruneOrphanExternalTargetsGraphMapper()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_map_when_external_targets_to_prune() async throws {
        // Given
        let app = Target.test(name: "App", destinations: [.iPhone], product: .app)
        let project = Project.test(path: try! AbsolutePath(validating: "/App"), targets: [app])
        let appDependency = GraphDependency.target(name: app.name, path: project.path)
        let directPackageProduct = Target.test(name: "DirectPackage", destinations: [.iPhone], product: .app)
        let transitivePackageProduct = Target.test(name: "TransitivePackage", destinations: [.iPhone], product: .app)
        let transitivePackageProductWithNoDestinations = Target.test(
            name: "TransitivePackageWithNoDestination",
            destinations: [],
            product: .app
        )
        let packageDevProduct = Target.test(name: "DevPackage", destinations: [.iPhone], product: .app)
        let packageProject = Project.test(
            path: try! AbsolutePath(validating: "/Package"),
            name: "Package",
            targets: [
                directPackageProduct,
                transitivePackageProduct,
                transitivePackageProductWithNoDestinations,
                packageDevProduct,
            ],
            isExternal: true
        )
        let directPackageProductDependency = GraphDependency.target(name: directPackageProduct.name, path: packageProject.path)
        let transitivePackageProductDependency = GraphDependency.target(
            name: transitivePackageProduct.name,
            path: packageProject.path
        )
        let transitivePackageProductWithNoDestinationsDependency = GraphDependency.target(
            name: transitivePackageProductWithNoDestinations.name,
            path: packageProject.path
        )

        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project, packageProject.path: packageProject],
            targets: [project.path: [
                app.name: app,
            ], packageProject.path: [
                directPackageProduct.name: directPackageProduct,
                transitivePackageProduct.name: transitivePackageProduct,
                transitivePackageProductWithNoDestinations.name: transitivePackageProductWithNoDestinations,
                packageDevProduct.name: packageDevProduct,
            ]],
            dependencies: [
                appDependency: Set([directPackageProductDependency]),
                directPackageProductDependency: Set([
                    transitivePackageProductDependency,
                    transitivePackageProductWithNoDestinationsDependency,
                ]),
            ]
        )

        // When
        let (gotGraph, _) = try await subject.map(graph: graph)

        // Then
        XCTAssertEqual(gotGraph.targets[project.path]?[app.name]?.prune, false)
        XCTAssertEqual(gotGraph.targets[packageProject.path]?[directPackageProduct.name]?.prune, false)
        XCTAssertEqual(gotGraph.targets[packageProject.path]?[transitivePackageProduct.name]?.prune, false)
        XCTAssertEqual(gotGraph.targets[packageProject.path]?[packageDevProduct.name]?.prune, true)
        XCTAssertEqual(gotGraph.targets[packageProject.path]?[transitivePackageProductWithNoDestinations.name]?.prune, true)
    }
}
