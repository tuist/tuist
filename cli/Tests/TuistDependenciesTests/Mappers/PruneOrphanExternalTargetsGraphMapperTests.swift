import Foundation
import Path
import Testing
import TuistCore
import TuistTesting
import XcodeGraph

@testable import TuistDependencies

struct PruneOrphanExternalTargetsGraphMapperTests {
    @Test func map_when_external_targets_to_prune() async throws {
        let subject = PruneOrphanExternalTargetsGraphMapper()
        // Given
        let app = Target.test(name: "App", destinations: [.iPhone], product: .app)
        let project = Project.test(path: try AbsolutePath(validating: "/App"), targets: [app])
        let appDependency = GraphDependency.target(name: app.name, path: project.path)
        let directPackageProduct = Target.test(name: "DirectPackage", destinations: [.iPhone], product: .app)
        let transitivePackageProduct = Target.test(name: "TransitivePackage", destinations: [.iPhone], product: .app)
        let transitivePackageProductWithNoDestinations = Target.test(
            name: "TransitivePackageWithNoDestination",
            destinations: [],
            product: .app
        )
        let packageDevProduct = Target.test(name: "DevPackage", destinations: [.iPhone], product: .app)
        let packageDevTestProduct = Target.test(
            name: "DevPackageTests",
            destinations: [.iPhone],
            product: .unitTests,
            metadata: .test(tags: [TargetTags.localSwiftPackageTest])
        )
        let remotePackageTestProduct = Target.test(
            name: "RemotePackageTests",
            destinations: [.iPhone],
            product: .unitTests
        )
        let packageProject = Project.test(
            path: try AbsolutePath(validating: "/Package"),
            name: "Package",
            targets: [
                directPackageProduct,
                transitivePackageProduct,
                transitivePackageProductWithNoDestinations,
                packageDevProduct,
                packageDevTestProduct,
                remotePackageTestProduct,
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

        for (path, target, shouldPrune) in [
            (project.path, app, false),
            (packageProject.path, directPackageProduct, false),
            (packageProject.path, transitivePackageProduct, false),
            (packageProject.path, packageDevProduct, true),
            (packageProject.path, packageDevTestProduct, true),
            (packageProject.path, remotePackageTestProduct, true),
            (packageProject.path, transitivePackageProductWithNoDestinations, true),
        ] {
            let mapped = try #require(gotGraph.projects[path]?.targets[target.name])
            #expect(mapped.metadata.tags.contains("tuist:prunable") == shouldPrune)
        }
    }
}
