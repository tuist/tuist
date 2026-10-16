import Foundation
import Path
import ProjectDescription
import Testing
import XcodeGraph
@testable import TuistLoader

struct DynamicPackageDependencyManifestMapperTests {
    @Test(arguments: [false, true])
    func mapsDynamicLinkageAndPlatformCondition(embedded: Bool) throws {
        let manifest = ProjectDescription.TargetDependency.package(
            product: "DynamicProduct",
            type: embedded ? .runtimeDynamicEmbedded : .runtimeDynamic,
            condition: .when([.ios])
        )
        let paths = GeneratorPaths(manifestDirectory: "/project", rootDirectory: "/project")

        let dependencies = try XcodeGraph.TargetDependency.from(
            manifest: manifest,
            generatorPaths: paths,
            externalDependencies: [:]
        )

        #expect(dependencies == [
            .package(
                product: "DynamicProduct",
                type: embedded ? .runtimeDynamicEmbedded : .runtimeDynamic,
                condition: .when([.ios])
            ),
        ])
        let data = try JSONEncoder().encode(manifest)
        #expect(try JSONDecoder().decode(ProjectDescription.TargetDependency.self, from: data) == manifest)
    }

    @Test
    func existingDeclarationSerializationRemainsCompatible() throws {
        let json = Data(#"{"package":{"product":"Shared","type":{"runtime":{}}}}"#.utf8)
        let manifest = try JSONDecoder().decode(ProjectDescription.TargetDependency.self, from: json)

        #expect(manifest == .package(product: "Shared"))
        let paths = GeneratorPaths(manifestDirectory: "/project", rootDirectory: "/project")
        #expect(try XcodeGraph.TargetDependency.from(
            manifest: manifest,
            generatorPaths: paths,
            externalDependencies: [:]
        ) == [.package(product: "Shared", type: .runtime)])
    }
}
