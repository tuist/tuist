import Foundation
import Path
import Testing
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

    func test_map_when_local_swift_package_test_target_depends_on_macro() async throws {
        // Given
        let directory = try temporaryPath()
        let packagesDirectory = directory.appending(component: "Dependencies")

        let appTarget = Target.test(name: "App", destinations: [.iPad, .iPhone])

        let externalLibrary = Target.test(
            name: "MyLibrary",
            destinations: [.iPad, .iPhone],
            product: .staticFramework
        )
        let externalMacro = Target.test(
            name: "MyMacro",
            destinations: [.mac],
            product: .macro
        )
        let externalLocalPackageTests = Target.test(
            name: "MyLibraryTests",
            destinations: [.iPad, .iPhone],
            product: .unitTests,
            dependencies: [
                .target(name: externalLibrary.name),
                .target(name: externalMacro.name),
            ],
            metadata: .test(tags: Set([TargetTags.localSwiftPackageTest]))
        )

        let project = Project.test(path: directory, targets: [appTarget])
        let externalProject = Project.test(
            path: packagesDirectory,
            targets: [externalLibrary, externalMacro, externalLocalPackageTests],
            type: .external(hash: nil)
        )

        let appTargetDependency = GraphDependency.target(name: appTarget.name, path: project.path)
        let externalLibraryDependency = GraphDependency.target(name: externalLibrary.name, path: externalProject.path)
        let externalMacroDependency = GraphDependency.target(name: externalMacro.name, path: externalProject.path)

        let graph = Graph.test(
            projects: [
                directory: project,
                packagesDirectory: externalProject,
            ],
            dependencies: [
                appTargetDependency: Set([externalLibraryDependency]),
                externalLibraryDependency: Set([externalMacroDependency]),
            ]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEqual(
            try XCTUnwrap(
                mappedGraph.projects[externalProject.path]?.targets[externalLocalPackageTests.name]?.supportedPlatforms
            ),
            Set([.iOS])
        )
    }

    func test_map_when_local_swift_package_test_target_depends_only_on_macro() async throws {
        // Given
        let directory = try temporaryPath()
        let packagesDirectory = directory.appending(component: "Dependencies")

        let appTarget = Target.test(name: "App", destinations: [.iPad, .iPhone])

        let externalLibrary = Target.test(
            name: "MyLibrary",
            destinations: [.iPad, .iPhone],
            product: .staticFramework
        )
        let externalMacro = Target.test(
            name: "MyMacro",
            destinations: [.mac],
            product: .macro
        )
        let externalLocalPackageTests = Target.test(
            name: "MyLibraryTests",
            destinations: [.iPad, .iPhone, .mac],
            product: .unitTests,
            dependencies: [
                .target(name: externalMacro.name),
            ],
            metadata: .test(tags: Set([TargetTags.localSwiftPackageTest]))
        )

        let project = Project.test(path: directory, targets: [appTarget])
        let externalProject = Project.test(
            path: packagesDirectory,
            targets: [externalLibrary, externalMacro, externalLocalPackageTests],
            type: .external(hash: nil)
        )

        let appTargetDependency = GraphDependency.target(name: appTarget.name, path: project.path)
        let externalLibraryDependency = GraphDependency.target(name: externalLibrary.name, path: externalProject.path)
        let externalMacroDependency = GraphDependency.target(name: externalMacro.name, path: externalProject.path)

        let graph = Graph.test(
            projects: [
                directory: project,
                packagesDirectory: externalProject,
            ],
            dependencies: [
                appTargetDependency: Set([externalLibraryDependency]),
                externalLibraryDependency: Set([externalMacroDependency]),
            ]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEqual(
            try XCTUnwrap(
                mappedGraph.projects[externalProject.path]?.targets[externalLocalPackageTests.name]?.destinations
            ),
            Set([.iPad, .iPhone, .mac])
        )
    }

    func test_map_when_local_swift_package_test_target_has_disjoint_linkable_deps() async throws {
        // Given
        let directory = try temporaryPath()
        let packagesDirectory = directory.appending(component: "Dependencies")

        let iosApp = Target.test(name: "iOSApp", destinations: [.iPad, .iPhone])
        let macApp = Target.test(name: "MacApp", destinations: [.mac], product: .app)

        let libA = Target.test(
            name: "LibA",
            destinations: [.iPad, .iPhone],
            product: .staticFramework
        )
        let libB = Target.test(
            name: "LibB",
            destinations: [.mac],
            product: .staticFramework
        )
        let externalLocalPackageTests = Target.test(
            name: "LibTests",
            destinations: [.iPad, .iPhone, .mac],
            product: .unitTests,
            dependencies: [
                .target(name: libA.name),
                .target(name: libB.name),
            ],
            metadata: .test(tags: Set([TargetTags.localSwiftPackageTest]))
        )

        let project = Project.test(path: directory, targets: [iosApp, macApp])
        let externalProject = Project.test(
            path: packagesDirectory,
            targets: [libA, libB, externalLocalPackageTests],
            type: .external(hash: nil)
        )

        let iosAppDependency = GraphDependency.target(name: iosApp.name, path: project.path)
        let macAppDependency = GraphDependency.target(name: macApp.name, path: project.path)
        let libADependency = GraphDependency.target(name: libA.name, path: externalProject.path)
        let libBDependency = GraphDependency.target(name: libB.name, path: externalProject.path)

        let graph = Graph.test(
            projects: [
                directory: project,
                packagesDirectory: externalProject,
            ],
            dependencies: [
                iosAppDependency: Set([libADependency]),
                macAppDependency: Set([libBDependency]),
            ]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let mappedTests = try XCTUnwrap(
            mappedGraph.projects[externalProject.path]?.targets[externalLocalPackageTests.name]
        )
        XCTAssertEqual(mappedTests.destinations, Set([.iPad, .iPhone, .mac]))
        XCTAssertFalse(mappedTests.metadata.tags.contains("tuist:prunable"))
    }

    func test_map_when_local_swift_package_test_target_is_not_widened_beyond_declared_destinations() async throws {
        // Given
        let directory = try temporaryPath()
        let packagesDirectory = directory.appending(component: "Dependencies")

        let iosApp = Target.test(name: "iOSApp", destinations: [.iPad, .iPhone])
        let watchApp = Target.test(name: "WatchApp", destinations: [.appleWatch], product: .app)

        let libA = Target.test(
            name: "LibA",
            destinations: [.iPad, .iPhone, .appleWatch],
            product: .staticFramework
        )
        let externalLocalPackageTests = Target.test(
            name: "LibTests",
            destinations: [.iPad, .iPhone],
            product: .unitTests,
            dependencies: [
                .target(name: libA.name),
            ],
            metadata: .test(tags: Set([TargetTags.localSwiftPackageTest]))
        )

        let project = Project.test(path: directory, targets: [iosApp, watchApp])
        let externalProject = Project.test(
            path: packagesDirectory,
            targets: [libA, externalLocalPackageTests],
            type: .external(hash: nil)
        )

        let iosAppDependency = GraphDependency.target(name: iosApp.name, path: project.path)
        let watchAppDependency = GraphDependency.target(name: watchApp.name, path: project.path)
        let externalLocalPackageTestsDependency = GraphDependency.target(
            name: externalLocalPackageTests.name,
            path: externalProject.path
        )
        let libADependency = GraphDependency.target(name: libA.name, path: externalProject.path)

        let graph = Graph.test(
            projects: [
                directory: project,
                packagesDirectory: externalProject,
            ],
            dependencies: [
                iosAppDependency: Set([libADependency]),
                watchAppDependency: Set([libADependency]),
                externalLocalPackageTestsDependency: Set([libADependency]),
            ]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let mappedTests = try XCTUnwrap(
            mappedGraph.projects[externalProject.path]?.targets[externalLocalPackageTests.name]
        )
        XCTAssertEqual(mappedTests.destinations, Set([.iPad, .iPhone]))
        XCTAssertFalse(mappedTests.metadata.tags.contains("tuist:prunable"))
    }

    func test_map_when_local_swift_package_test_target_depends_on_platform_conditional_library() async throws {
        // Given
        let directory = try temporaryPath()
        let packagesDirectory = directory.appending(component: "Dependencies")

        let iosApp = Target.test(name: "iOSApp", destinations: [.iPad, .iPhone])
        let watchApp = Target.test(name: "WatchApp", destinations: [.appleWatch], product: .app)

        let libA = Target.test(
            name: "LibA",
            destinations: [.iPad, .iPhone, .appleWatch],
            product: .staticFramework
        )
        let iosCondition = try XCTUnwrap(PlatformCondition.when([.ios]))
        let externalLocalPackageTests = Target.test(
            name: "LibTests",
            destinations: [.iPad, .iPhone, .appleWatch],
            product: .unitTests,
            dependencies: [
                .target(name: libA.name, condition: iosCondition),
            ],
            metadata: .test(tags: Set([TargetTags.localSwiftPackageTest]))
        )

        let project = Project.test(path: directory, targets: [iosApp, watchApp])
        let externalProject = Project.test(
            path: packagesDirectory,
            targets: [libA, externalLocalPackageTests],
            type: .external(hash: nil)
        )

        let iosAppDependency = GraphDependency.target(name: iosApp.name, path: project.path)
        let watchAppDependency = GraphDependency.target(name: watchApp.name, path: project.path)
        let externalLocalPackageTestsDependency = GraphDependency.target(
            name: externalLocalPackageTests.name,
            path: externalProject.path
        )
        let libADependency = GraphDependency.target(name: libA.name, path: externalProject.path)

        let graph = Graph.test(
            projects: [
                directory: project,
                packagesDirectory: externalProject,
            ],
            dependencies: [
                iosAppDependency: Set([libADependency]),
                watchAppDependency: Set([libADependency]),
                externalLocalPackageTestsDependency: Set([libADependency]),
            ],
            dependencyConditions: [
                GraphEdge(from: externalLocalPackageTestsDependency, to: libADependency): iosCondition,
            ]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let mappedTests = try XCTUnwrap(
            mappedGraph.projects[externalProject.path]?.targets[externalLocalPackageTests.name]
        )
        XCTAssertEqual(mappedTests.destinations, Set([.iPad, .iPhone]))
        XCTAssertFalse(mappedTests.metadata.tags.contains("tuist:prunable"))
    }
}

struct ExternalProjectsPlatformNarrowerGraphMapperConditionTests {
    /// A macro-only helper links SwiftPM's prebuilt swift-syntax on macOS and keeps its source dependency for the other
    /// platforms. Once narrowed to macOS, that dependency can never apply, and keeping the edge fails the dependency lint
    /// when another target keeps swift-syntax around for iOS. The target's own dependencies must lose it too: binary-cache
    /// hashing hashes them in the order of the graph's edges, so a dependency without an edge has no hash yet.
    @Test func map_removesExternalDependenciesWhoseConditionExcludesTheNarrowedPlatforms() async throws {
        // Given
        let directory: AbsolutePath = "/Project"
        let packagesDirectory = directory.appending(component: "Dependencies")

        let appTarget = Target.test(name: "App", destinations: [.iPhone])
        let libraryCondition = try #require(PlatformCondition.when([.ios]))
        let macroSupportCondition = try #require(PlatformCondition.when([.ios, .catalyst, .tvos, .watchos, .visionos]))
        let library = Target.test(
            name: "Library",
            destinations: Set(Destination.allCases),
            product: .staticFramework,
            dependencies: [.target(name: "Macro"), .target(name: "SwiftSyntax", condition: libraryCondition)]
        )
        let macro = Target.test(
            name: "Macro",
            destinations: [.mac],
            product: .macro,
            dependencies: [.target(name: "MacroSupport")]
        )
        let macroSupport = Target.test(
            name: "MacroSupport",
            destinations: Set(Destination.allCases),
            product: .staticFramework,
            dependencies: [.target(name: "SwiftSyntax", condition: macroSupportCondition)]
        )
        let swiftSyntax = Target.test(name: "SwiftSyntax", destinations: Set(Destination.allCases), product: .staticFramework)

        let project = Project.test(path: directory, targets: [appTarget])
        let externalProject = Project.test(
            path: packagesDirectory,
            targets: [library, macro, macroSupport, swiftSyntax],
            type: .external(hash: nil)
        )

        let appDependency = GraphDependency.target(name: appTarget.name, path: project.path)
        let libraryDependency = GraphDependency.target(name: library.name, path: externalProject.path)
        let macroDependency = GraphDependency.target(name: macro.name, path: externalProject.path)
        let macroSupportDependency = GraphDependency.target(name: macroSupport.name, path: externalProject.path)
        let swiftSyntaxDependency = GraphDependency.target(name: swiftSyntax.name, path: externalProject.path)

        let librarySwiftSyntaxEdge = GraphEdge(from: libraryDependency, to: swiftSyntaxDependency)
        let macroSupportSwiftSyntaxEdge = GraphEdge(from: macroSupportDependency, to: swiftSyntaxDependency)
        let graph = Graph.test(
            projects: [
                directory: project,
                packagesDirectory: externalProject,
            ],
            dependencies: [
                appDependency: [libraryDependency],
                libraryDependency: [macroDependency, swiftSyntaxDependency],
                macroDependency: [macroSupportDependency],
                macroSupportDependency: [swiftSyntaxDependency],
            ],
            dependencyConditions: [
                librarySwiftSyntaxEdge: libraryCondition,
                macroSupportSwiftSyntaxEdge: macroSupportCondition,
            ]
        )

        // When
        let (mappedGraph, _, _) = try await ExternalProjectsPlatformNarrowerGraphMapper().map(
            graph: graph,
            environment: MapperEnvironment()
        )

        // Then
        #expect(mappedGraph.projects[externalProject.path]?.targets[macroSupport.name]?.destinations == [.mac])
        #expect(mappedGraph.projects[externalProject.path]?.targets[macroSupport.name]?.dependencies == [])
        #expect(mappedGraph.projects[externalProject.path]?.targets[library.name]?.dependencies == library.dependencies)
        #expect(mappedGraph.projects[externalProject.path]?.targets[swiftSyntax.name]?.destinations == [.iPhone])
        #expect((mappedGraph.dependencies[macroSupportDependency] ?? []).isEmpty)
        #expect(mappedGraph.dependencyConditions[macroSupportSwiftSyntaxEdge] == nil)
        #expect(mappedGraph.dependencies[libraryDependency] == [macroDependency, swiftSyntaxDependency])
        #expect(mappedGraph.dependencyConditions[librarySwiftSyntaxEdge] == .when([.ios]))
    }
}
