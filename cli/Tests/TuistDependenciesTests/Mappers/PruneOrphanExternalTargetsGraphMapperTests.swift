import Foundation
import Path
import TuistCore
import TuistTesting
import XcodeGraph
import XCTest

@testable import TuistDependencies

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
            type: .external(hash: nil)
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
            dependencies: [
                appDependency: Set([directPackageProductDependency]),
                directPackageProductDependency: Set([
                    transitivePackageProductDependency,
                    transitivePackageProductWithNoDestinationsDependency,
                ]),
            ]
        )

        // When
        let (gotGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then

        XCTAssertEqual(gotGraph.projects[project.path]?.targets[app.name]?.metadata.tags.contains("tuist:prunable"), false)
        XCTAssertEqual(
            gotGraph.projects[packageProject.path]?.targets[directPackageProduct.name]?.metadata.tags.contains("tuist:prunable"),
            false
        )
        XCTAssertEqual(
            gotGraph.projects[packageProject.path]?.targets[transitivePackageProduct.name]?.metadata.tags
                .contains("tuist:prunable"),
            false
        )
        XCTAssertEqual(
            gotGraph.projects[packageProject.path]?.targets[packageDevProduct.name]?.metadata.tags.contains("tuist:prunable"),
            true
        )
        XCTAssertEqual(
            gotGraph.projects[packageProject.path]?.targets[transitivePackageProductWithNoDestinations.name]?.metadata.tags
                .contains("tuist:prunable"),
            true
        )
    }
}
