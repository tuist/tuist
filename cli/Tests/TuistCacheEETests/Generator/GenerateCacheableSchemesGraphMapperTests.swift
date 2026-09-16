import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
import XcodeGraph
import XCTest

@testable import TuistCacheEE
@testable import TuistTesting

final class GenerateCacheableSchemesGraphMapperTests: TuistUnitTestCase {
    func test_generate_binary_and_bundles_schemes() async throws {
        // Given
        let directory = try temporaryPath()

        let targetA = Target.test(name: "A", destinations: [.iPhone], product: .framework)
        let targetB = Target.test(name: "B", destinations: [.iPhone], product: .app)
        let targetC = Target.test(name: "C", destinations: [.mac], product: .framework)
        let staticLibrary = Target.test(name: "StaticLibrary", destinations: [.iPhone], product: .staticLibrary)
        let dynamicLibrary = Target.test(name: "DynamicLibrary", destinations: [.mac], product: .dynamicLibrary)
        let bundle = Target.test(name: "Bundle", destinations: [.appleTv], product: .bundle)
        let macro = Target.test(name: "Macro", destinations: [.appleTv], product: .macro)

        let includedTargets = [targetA, staticLibrary, targetC, dynamicLibrary, bundle, macro].map(\.name)
        let subject = GenerateCacheableSchemesGraphMapper(targets: [
            .iOS: Set([.named(targetA.name), .named(staticLibrary.name)]),
            .macOS: Set([.named(targetC.name), .named(dynamicLibrary.name)]),
            .tvOS: Set([.named(bundle.name), .named(macro.name)]),
        ])
        let projectAPath = directory.appending(component: "ProjectA")
        let projectBPath = directory.appending(component: "ProjectB")
        let projectA = Project.test(path: projectAPath, name: "A", targets: [targetA, staticLibrary, bundle, macro])
        let projectB = Project.test(path: projectBPath, name: "B", targets: [targetB, targetC, dynamicLibrary])

        let graph = Graph.test(
            workspace: Workspace.test(projects: [projectAPath, projectBPath]),
            projects: [
                projectAPath: projectA,
                projectBPath: projectB,
            ]
        )

        // When
        let (updatedGraph, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEqual(
            updatedGraph.workspace.schemes.map(\.name),
            [
                "Binaries-Cache-iOS",
                "Bundles-Cache-iOS",
                "Macros-Cache-iOS",
                "Binaries-Cache-macOS",
                "Bundles-Cache-macOS",
                "Macros-Cache-macOS",
                "Binaries-Cache-tvOS",
                "Bundles-Cache-tvOS",
                "Macros-Cache-tvOS",
                "Binaries-Cache-watchOS",
                "Bundles-Cache-watchOS",
                "Macros-Cache-watchOS",
                "Binaries-Cache-visionOS",
                "Bundles-Cache-visionOS",
                "Macros-Cache-visionOS",
            ]
        )

        XCTAssertEqual(
            updatedGraph.workspace.schemes.first(where: { $0.name == "Binaries-Cache-iOS" })?
                .buildAction?.targets
                .map(\.name),
            [
                "A",
                "StaticLibrary",
            ]
        )
        XCTAssertEqual(
            updatedGraph.workspace.schemes.first(where: { $0.name == "Binaries-Cache-macOS" })?
                .buildAction?.targets
                .map(\.name),
            [
                "C",
                "DynamicLibrary",
            ]
        )
        XCTAssertEqual(
            updatedGraph.workspace.schemes.first(where: { $0.name == "Bundles-Cache-tvOS" })?
                .buildAction?.targets
                .map(\.name),
            [
                "Bundle",
            ]
        )

        XCTAssertEqual(
            updatedGraph.workspace.schemes.first(where: { $0.name == "Macros-Cache-tvOS" })?
                .buildAction?.targets.map(\.name),
            [
                "Macro",
            ]
        )

        XCTAssertEqual(
            updatedGraph.workspace.schemes.flatMap { $0.buildAction?.targets ?? [] }.map(
                \.name
            ), includedTargets
        )
        XCTAssertTrue(sideEffects.isEmpty)
    }

    func test_generate_catalyst_scheme_for_targets_that_support_catalyst() async throws {
        // Given
        let directory = try temporaryPath()

        let targetWithCatalyst = Target.test(name: "WithCatalyst", destinations: [.iPhone, .macCatalyst], product: .framework)
        let targetWithoutCatalyst = Target.test(name: "WithoutCatalyst", destinations: [.iPhone], product: .framework)

        let subject = GenerateCacheableSchemesGraphMapper(targets: [
            .iOS: Set([.named(targetWithCatalyst.name), .named(targetWithoutCatalyst.name)]),
        ])
        let projectPath = directory.appending(component: "App")
        let project = Project.test(path: projectPath, name: "App", targets: [targetWithCatalyst, targetWithoutCatalyst])

        let graph = Graph.test(
            workspace: Workspace.test(projects: [projectPath]),
            projects: [projectPath: project]
        )

        // When
        let (updatedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertTrue(updatedGraph.workspace.schemes.map(\.name).contains("Binaries-Cache-Catalyst"))

        XCTAssertEqual(
            updatedGraph.workspace.schemes.first(where: { $0.name == "Binaries-Cache-Catalyst" })?
                .buildAction?.targets
                .map(\.name),
            [
                "WithCatalyst",
            ]
        )

        XCTAssertEqual(
            updatedGraph.workspace.schemes.first(where: { $0.name == "Binaries-Cache-iOS" })?
                .buildAction?.targets
                .map(\.name),
            [
                "WithCatalyst",
                "WithoutCatalyst",
            ]
        )
    }

    func test_does_not_generate_catalyst_scheme_when_no_targets_support_catalyst() async throws {
        // Given
        let directory = try temporaryPath()

        let targetA = Target.test(name: "A", destinations: [.iPhone], product: .framework)
        let targetB = Target.test(name: "B", destinations: [.iPhone], product: .framework)

        let subject = GenerateCacheableSchemesGraphMapper(targets: [
            .iOS: Set([.named(targetA.name), .named(targetB.name)]),
        ])
        let projectPath = directory.appending(component: "App")
        let project = Project.test(path: projectPath, name: "App", targets: [targetA, targetB])

        let graph = Graph.test(
            workspace: Workspace.test(projects: [projectPath]),
            projects: [projectPath: project]
        )

        // When
        let (updatedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertFalse(updatedGraph.workspace.schemes.map(\.name).contains("Binaries-Cache-Catalyst"))
    }
}

struct GenerateCacheableSchemesGraphMapperSourceDependenciesTests {
    @Test(.inTemporaryDirectory) func binariesSchemeIncludesSourceDependenciesOfTheTargetsToCache() async throws {
        // Given
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = directory.appending(component: "App")

        let feature = Target.test(name: "Feature", destinations: [.iPhone], product: .staticFramework)
        let servicesMockSupport = Target.test(
            name: "ServicesMockSupport",
            destinations: [.iPhone],
            product: .staticFramework
        )
        let services = Target.test(name: "Services", destinations: [.iPhone], product: .staticFramework)
        let resources = Target.test(name: "Resources", destinations: [.iPhone], product: .bundle)
        let macOnlyDependency = Target.test(
            name: "MacOnlyDependency",
            destinations: [.iPhone, .mac],
            product: .staticFramework
        )
        let unrelated = Target.test(name: "Unrelated", destinations: [.iPhone], product: .staticFramework)
        let cachedFramework = GraphDependency.testXCFramework(path: directory.appending(component: "Cached.xcframework"))

        let subject = GenerateCacheableSchemesGraphMapper(targets: [
            .iOS: Set([.named(feature.name), .named(services.name)]),
        ])
        let project = Project.test(
            path: projectPath,
            name: "App",
            targets: [feature, servicesMockSupport, services, resources, macOnlyDependency, unrelated]
        )
        let featureDependency = GraphDependency.target(name: feature.name, path: projectPath)
        let servicesMockSupportDependency = GraphDependency.target(name: servicesMockSupport.name, path: projectPath)
        let macOnlyDependencyDependency = GraphDependency.target(name: macOnlyDependency.name, path: projectPath)

        let graph = Graph.test(
            workspace: Workspace.test(projects: [projectPath]),
            projects: [projectPath: project],
            dependencies: [
                featureDependency: [
                    servicesMockSupportDependency,
                    macOnlyDependencyDependency,
                    cachedFramework,
                ],
                servicesMockSupportDependency: [
                    .target(name: services.name, path: projectPath),
                    .target(name: resources.name, path: projectPath),
                ],
            ],
            dependencyConditions: [
                GraphEdge(from: featureDependency, to: macOnlyDependencyDependency): try #require(
                    PlatformCondition.when([.macos])
                ),
            ]
        )

        // When
        let (updatedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        #expect(
            updatedGraph.workspace.schemes.first(where: { $0.name == "Binaries-Cache-iOS" })?
                .buildAction?.targets
                .map(\.name) == [
                    "Feature",
                    "Services",
                    "ServicesMockSupport",
                ]
        )
    }
}
