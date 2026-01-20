import Foundation
import TuistCore
import TuistTesting
import XcodeGraph
import XCTest

@testable import TuistDependencies

final class ExternalProjectsPlatformNarrowerGraphMapperTests: TuistUnitTestCase {
    var subject: ExternalProjectsPlatformNarrowerGraphMapper!

    override func setUp() {
        super.setUp()
        subject = ExternalProjectsPlatformNarrowerGraphMapper()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_map_when_external_dependency_without_platform_filter() async throws {
        // Given
        let directory = try temporaryPath()
        let packagesDirectory = directory.appending(component: "Dependencies")

        let appTarget = Target.test(name: "App", destinations: [.iPad, .iPhone])
        let externalPackage = Target.test(
            name: "Package",
            destinations: [.iPad, .iPhone, .appleWatch, .appleTv, .mac],
            product: .framework
        )

        let project = Project.test(path: directory, targets: [appTarget])
        let externalProject = Project.test(path: packagesDirectory, targets: [externalPackage], type: .external(hash: nil))

        let appTargetDependency = GraphDependency.target(name: appTarget.name, path: project.path)
        let externalPackageDependency = GraphDependency.target(name: externalPackage.name, path: externalProject.path)

        let graph = Graph.test(
            projects: [
                directory: project,
                packagesDirectory: externalProject,
            ],
            dependencies: [
                appTargetDependency: Set([externalPackageDependency]),
            ]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then

        XCTAssertEqual(
            try XCTUnwrap(mappedGraph.projects[project.path]?.targets[appTarget.name])?.supportedPlatforms,
            Set([.iOS])
        )
        XCTAssertEqual(
            try XCTUnwrap(mappedGraph.projects[externalProject.path]?.targets[externalPackage.name]?.supportedPlatforms),
            Set([.iOS])
        )
    }

    func test_map_when_external_with_platform_filter() async throws {
        // Given
        let directory = try temporaryPath()
        let packagesDirectory = directory.appending(component: "Dependencies")

        let appTarget = Target.test(name: "App", destinations: [.iPad, .iPhone, .appleWatch, .appleTv, .mac])
        let externalPackage = Target.test(
            name: "Package",
            destinations: [.iPhone, .iPad, .appleWatch],
            product: .framework,
            deploymentTargets: .init(iOS: "16.0", macOS: nil, watchOS: "9.0", tvOS: nil, visionOS: nil)
        )

        let project = Project.test(path: directory, targets: [appTarget])
        let externalProject = Project.test(path: packagesDirectory, targets: [externalPackage], type: .external(hash: nil))

        let appTargetDependency = GraphDependency.target(name: appTarget.name, path: project.path)
        let externalPackageDependency = GraphDependency.target(name: externalPackage.name, path: externalProject.path)

        // Only use the external target on iOS
        let dependencyCondition = try XCTUnwrap(PlatformCondition.when([.ios]))

        let graph = Graph.test(
            projects: [
                directory: project,
                packagesDirectory: externalProject,
            ],
            dependencies: [
                appTargetDependency: Set([externalPackageDependency]),
            ],
            dependencyConditions: [
                GraphEdge(from: appTargetDependency, to: externalPackageDependency): dependencyCondition,
            ]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then

        XCTAssertEqual(
            try XCTUnwrap(mappedGraph.projects[project.path]?.targets[appTarget.name]?.supportedPlatforms),
            Set([.iOS, .macOS, .tvOS, .watchOS])
        )
        XCTAssertEqual(
            try XCTUnwrap(mappedGraph.projects[externalProject.path]?.targets[externalPackage.name]?.supportedPlatforms),
            Set([.iOS])
        )
        XCTAssertEqual(
            try XCTUnwrap(mappedGraph.projects[externalProject.path]?.targets[externalPackage.name]?.deploymentTargets),
            .iOS("16.0")
        )
    }

    func test_map_when_external_dependencies_end_with_no_platforms() async throws {
        // Given
        let directory = try temporaryPath()
        let packagesDirectory = directory.appending(component: "Dependencies")

        let appTarget = Target.test(name: "App", destinations: [.iPad, .iPhone, .appleWatch, .appleTv, .mac])
        let externalPackage = Target.test(
            name: "Package",
            destinations: [.appleWatch],
            product: .framework,
            deploymentTargets: .init(iOS: nil, macOS: nil, watchOS: "9.0", tvOS: nil, visionOS: nil)
        )

        let project = Project.test(path: directory, targets: [appTarget])
        let externalProject = Project.test(path: packagesDirectory, targets: [externalPackage], type: .external(hash: nil))

        let appTargetDependency = GraphDependency.target(name: appTarget.name, path: project.path)
        let externalPackageDependency = GraphDependency.target(name: externalPackage.name, path: externalProject.path)

        // Only use the external target on iOS
        let dependencyCondition = try XCTUnwrap(PlatformCondition.when([.ios]))

        let graph = Graph.test(
            projects: [
                directory: project,
                packagesDirectory: externalProject,
            ],
            dependencies: [
                appTargetDependency: Set([externalPackageDependency]),
            ],
            dependencyConditions: [
                GraphEdge(from: appTargetDependency, to: externalPackageDependency): dependencyCondition,
            ]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then

        XCTAssertEqual(
            try XCTUnwrap(mappedGraph.projects[project.path]?.targets[appTarget.name]?.supportedPlatforms),
            Set([.iOS, .macOS, .tvOS, .watchOS])
        )
        XCTAssertEqual(
            try XCTUnwrap(mappedGraph.projects[externalProject.path]?.targets[externalPackage.name]?.supportedPlatforms),
            Set([])
        )
        XCTAssertEqual(
            try XCTUnwrap(mappedGraph.projects[externalProject.path]?.targets[externalPackage.name]?.deploymentTargets),
            DeploymentTargets(iOS: nil, macOS: nil, watchOS: nil, tvOS: nil, visionOS: nil)
        )
        XCTAssertTrue(try XCTUnwrap(mappedGraph.projects[externalProject.path]?.targets[externalPackage.name]?.metadata.tags)
            .contains("tuist:prunable")
        )
    }

    func test_map_when_external_transitive_dependency_without_platform_filter() async throws {
        // Given
        let directory = try temporaryPath()
        let packagesDirectory = directory.appending(component: "Dependencies")

        let appTarget = Target.test(name: "App", destinations: [.iPad, .iPhone])
        let directExternalPackage = Target.test(
            name: "Direct",
            destinations: [.iPad, .iPhone],
            product: .framework
        )
        let transitiveExternalPackage = Target.test(
            name: "Transitive",
            destinations: [.iPad, .iPhone, .appleWatch, .appleTv, .mac, .macWithiPadDesign, .macCatalyst],
            product: .framework
        )

        let project = Project.test(path: directory, targets: [appTarget])
        let externalProject = Project.test(
            path: packagesDirectory,
            targets: [directExternalPackage, transitiveExternalPackage],
            type: .external(hash: nil)
        )

        let appTargetDependency = GraphDependency.target(name: appTarget.name, path: project.path)
        let directExternalPackageDependency = GraphDependency.target(name: directExternalPackage.name, path: externalProject.path)
        let transitiveExternalPackageDependency = GraphDependency.target(
            name: transitiveExternalPackage.name,
            path: externalProject.path
        )

        let graph = Graph.test(
            projects: [
                directory: project,
                packagesDirectory: externalProject,
            ],
            dependencies: [
                appTargetDependency: Set([directExternalPackageDependency]),
                directExternalPackageDependency: Set([transitiveExternalPackageDependency]),
            ]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then

        XCTAssertEqual(
            try XCTUnwrap(mappedGraph.projects[project.path]?.targets[appTarget.name]?.supportedPlatforms),
            Set([.iOS])
        )
        XCTAssertEqual(
            try XCTUnwrap(mappedGraph.projects[externalProject.path]?.targets[directExternalPackage.name]?.supportedPlatforms),
            Set([.iOS])
        )
        XCTAssertEqual(
            try XCTUnwrap(
                mappedGraph.projects[externalProject.path]?.targets[transitiveExternalPackage.name]?
                    .supportedPlatforms
            ),
            Set([.iOS])
        )
        XCTAssertEqual(
            try XCTUnwrap(
                mappedGraph.projects[externalProject.path]?.targets[transitiveExternalPackage.name]?
                    .destinations
            ),
            Set([.iPad, .iPhone])
        )
    }

    func test_map_excludes_catalyst_when_app_does_not_support_it() async throws {
        // Given
        let directory = try temporaryPath()
        let packagesDirectory = directory.appending(component: "Dependencies")

        let appTarget = Target.test(name: "App", destinations: [.iPad, .iPhone])
        let externalPackage = Target.test(
            name: "Package",
            destinations: [.iPad, .iPhone, .macCatalyst],
            product: .framework
        )

        let project = Project.test(path: directory, targets: [appTarget])
        let externalProject = Project.test(path: packagesDirectory, targets: [externalPackage], type: .external(hash: nil))

        let appTargetDependency = GraphDependency.target(name: appTarget.name, path: project.path)
        let externalPackageDependency = GraphDependency.target(name: externalPackage.name, path: externalProject.path)

        let graph = Graph.test(
            projects: [
                directory: project,
                packagesDirectory: externalProject,
            ],
            dependencies: [
                appTargetDependency: Set([externalPackageDependency]),
            ]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let mappedExternalPackage = try XCTUnwrap(
            mappedGraph.projects[externalProject.path]?.targets[externalPackage.name]
        )
        XCTAssertEqual(mappedExternalPackage.destinations, Set([.iPad, .iPhone]))
        XCTAssertFalse(mappedExternalPackage.destinations.contains(.macCatalyst))
    }

    func test_map_includes_catalyst_when_app_supports_it() async throws {
        // Given
        let directory = try temporaryPath()
        let packagesDirectory = directory.appending(component: "Dependencies")

        let appTarget = Target.test(name: "App", destinations: [.iPad, .iPhone, .macCatalyst])
        let externalPackage = Target.test(
            name: "Package",
            destinations: [.iPad, .iPhone, .macCatalyst, .mac],
            product: .framework
        )

        let project = Project.test(path: directory, targets: [appTarget])
        let externalProject = Project.test(path: packagesDirectory, targets: [externalPackage], type: .external(hash: nil))

        let appTargetDependency = GraphDependency.target(name: appTarget.name, path: project.path)
        let externalPackageDependency = GraphDependency.target(name: externalPackage.name, path: externalProject.path)

        let graph = Graph.test(
            projects: [
                directory: project,
                packagesDirectory: externalProject,
            ],
            dependencies: [
                appTargetDependency: Set([externalPackageDependency]),
            ]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let mappedExternalPackage = try XCTUnwrap(
            mappedGraph.projects[externalProject.path]?.targets[externalPackage.name]
        )
        XCTAssertEqual(mappedExternalPackage.destinations, Set([.iPad, .iPhone, .macCatalyst]))
        XCTAssertTrue(mappedExternalPackage.destinations.contains(.macCatalyst))
        XCTAssertFalse(mappedExternalPackage.destinations.contains(.mac))
    }

    func test_map_when_external_macro_dependency() async throws {
        // Given
        let directory = try temporaryPath()
        let packagesDirectory = directory.appending(component: "Dependencies")

        let appTarget = Target.test(name: "App", destinations: [.iPad, .iPhone])
        let externalMacroFramework = Target.test(
            name: "MacroFramework",
            destinations: [.iPad, .iPhone],
            product: .staticFramework
        )
        let externalMacroExecutable = Target.test(name: "MacroExcutable", destinations: [.mac], product: .macro)

        let project = Project.test(path: directory, targets: [appTarget])
        let externalProject = Project.test(
            path: packagesDirectory,
            targets: [externalMacroFramework, externalMacroExecutable],
            type: .external(hash: nil)
        )

        let appTargetDependency = GraphDependency.target(name: appTarget.name, path: project.path)
        let externalMacroFrameworkDependency = GraphDependency.target(
            name: externalMacroFramework.name,
            path: externalProject.path
        )
        let externalMacroExecutableDependency = GraphDependency.target(
            name: externalMacroExecutable.name,
            path: externalProject.path
        )

        let graph = Graph.test(
            projects: [
                directory: project,
                packagesDirectory: externalProject,
            ],
            dependencies: [
                appTargetDependency: Set([externalMacroFrameworkDependency]),
                externalMacroFrameworkDependency: Set([externalMacroExecutableDependency]),
            ]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEqual(
            try XCTUnwrap(mappedGraph.projects[project.path]?.targets[appTarget.name]?.supportedPlatforms),
            Set([.iOS])
        )
        XCTAssertEqual(
            try XCTUnwrap(mappedGraph.projects[externalProject.path]?.targets[externalMacroFramework.name]?.supportedPlatforms),
            Set([.iOS])
        )
        XCTAssertEqual(
            try XCTUnwrap(mappedGraph.projects[externalProject.path]?.targets[externalMacroExecutable.name]?.supportedPlatforms),
            Set([.macOS])
        )
    }
}
