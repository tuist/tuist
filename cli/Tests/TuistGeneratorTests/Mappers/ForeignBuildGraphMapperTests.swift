import FileSystem
import Foundation
import Path
import XcodeGraph
import XCTest
@testable import TuistCore
@testable import TuistGenerator
@testable import TuistTesting

final class ForeignBuildGraphMapperTests: TuistUnitTestCase {
    var subject: ForeignBuildGraphMapper!
    var scriptRunnerCallCount: Int!
    var lastScriptRunnerArgs: (name: String, script: String, projectPath: AbsolutePath)?

    override func setUp() {
        super.setUp()
        scriptRunnerCallCount = 0
        subject = ForeignBuildGraphMapper(
            scriptRunner: { [unowned self] name, script, projectPath in
                self.scriptRunnerCallCount += 1
                self.lastScriptRunnerArgs = (name, script, projectPath)
            }
        )
    }

    override func tearDown() {
        subject = nil
        scriptRunnerCallCount = nil
        lastScriptRunnerArgs = nil
        super.tearDown()
    }

    func test_map_createsAggregateTargetForForeignBuildDependency() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/SharedKMP.xcframework")
        let target = Target.test(
            name: "Framework1",
            dependencies: [
                .foreignBuild(
                    name: "SharedKMP",
                    script: "gradle build",
                    output: .xcframework(path: outputPath, linking: .dynamic),
                    cacheInputs: []
                ),
            ]
        )
        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let mappedProject = try XCTUnwrap(mappedGraph.projects[projectPath])
        let aggregateTarget = try XCTUnwrap(mappedProject.targets["ForeignBuild_SharedKMP"])

        XCTAssertEqual(aggregateTarget.name, "ForeignBuild_SharedKMP")
        XCTAssertEqual(aggregateTarget.product, .staticLibrary)
        XCTAssertEqual(aggregateTarget.bundleId, "tuist.foreign-build.SharedKMP")
        XCTAssertEqual(aggregateTarget.metadata.tags, ["tuist:foreign-build-aggregate"])
        XCTAssertEqual(aggregateTarget.scripts.count, 1)
        XCTAssertEqual(aggregateTarget.scripts.first?.name, "Foreign Build: SharedKMP")
        XCTAssertEqual(aggregateTarget.scripts.first?.script, .embedded("gradle build"))
        XCTAssertEqual(aggregateTarget.scripts.first?.outputPaths, [outputPath.pathString])
    }

    func test_map_addsDependencyFromConsumingTargetToAggregateTarget() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/SharedKMP.xcframework")
        let target = Target.test(
            name: "Framework1",
            dependencies: [
                .foreignBuild(
                    name: "SharedKMP",
                    script: "gradle build",
                    output: .xcframework(path: outputPath, linking: .dynamic),
                    cacheInputs: []
                ),
            ]
        )
        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let consumingDep = GraphDependency.target(name: "Framework1", path: projectPath)
        let aggregateDep = GraphDependency.target(name: "ForeignBuild_SharedKMP", path: projectPath)
        XCTAssertTrue(mappedGraph.dependencies[consumingDep]?.contains(aggregateDep) == true)
        XCTAssertEqual(mappedGraph.dependencies[aggregateDep], Set())
    }

    func test_map_reusesAggregateTargetForSameForeignBuildName() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/SharedKMP.xcframework")
        let target1 = Target.test(
            name: "Framework1",
            dependencies: [
                .foreignBuild(
                    name: "SharedKMP",
                    script: "gradle build",
                    output: .xcframework(path: outputPath, linking: .dynamic),
                    cacheInputs: []
                ),
            ]
        )
        let target2 = Target.test(
            name: "Framework2",
            dependencies: [
                .foreignBuild(
                    name: "SharedKMP",
                    script: "gradle build",
                    output: .xcframework(path: outputPath, linking: .dynamic),
                    cacheInputs: []
                ),
            ]
        )
        let project = Project.test(path: projectPath, targets: [target1, target2])
        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let mappedProject = try XCTUnwrap(mappedGraph.projects[projectPath])
        let aggregateTargets = mappedProject.targets.values.filter { $0.name.hasPrefix("ForeignBuild_") }
        XCTAssertEqual(aggregateTargets.count, 1)

        let aggregateDep = GraphDependency.target(name: "ForeignBuild_SharedKMP", path: projectPath)
        let dep1 = GraphDependency.target(name: "Framework1", path: projectPath)
        let dep2 = GraphDependency.target(name: "Framework2", path: projectPath)
        XCTAssertTrue(mappedGraph.dependencies[dep1]?.contains(aggregateDep) == true)
        XCTAssertTrue(mappedGraph.dependencies[dep2]?.contains(aggregateDep) == true)
    }

    func test_map_createsSeparateAggregateTargetsForDifferentForeignBuilds() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath1 = try AbsolutePath(validating: "/Project/build/SharedKMP.xcframework")
        let outputPath2 = try AbsolutePath(validating: "/Project/build/RustLib.a")
        let target = Target.test(
            name: "App",
            dependencies: [
                .foreignBuild(
                    name: "SharedKMP",
                    script: "gradle build",
                    output: .xcframework(path: outputPath1, linking: .dynamic),
                    cacheInputs: []
                ),
                .foreignBuild(
                    name: "RustLib",
                    script: "cargo build",
                    output: .library(path: outputPath2, publicHeaders: try AbsolutePath(validating: "/Project/headers"), swiftModuleMap: nil, linking: .static),
                    cacheInputs: []
                ),
            ]
        )
        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let mappedProject = try XCTUnwrap(mappedGraph.projects[projectPath])
        XCTAssertNotNil(mappedProject.targets["ForeignBuild_SharedKMP"])
        XCTAssertNotNil(mappedProject.targets["ForeignBuild_RustLib"])
    }

    func test_map_setsInputPathsFromCacheInputs() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/SharedKMP.xcframework")
        let srcFolder = try AbsolutePath(validating: "/Project/SharedKMP/src")
        let gradleFile = try AbsolutePath(validating: "/Project/SharedKMP/build.gradle.kts")
        let target = Target.test(
            name: "Framework1",
            dependencies: [
                .foreignBuild(
                    name: "SharedKMP",
                    script: "gradle build",
                    output: .xcframework(path: outputPath, linking: .dynamic),
                    cacheInputs: [
                        .folder(srcFolder),
                        .file(gradleFile),
                        .glob("/Project/SharedKMP/**/*.kt"),
                        .script("git rev-parse HEAD"),
                    ]
                ),
            ]
        )
        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let mappedProject = try XCTUnwrap(mappedGraph.projects[projectPath])
        let aggregateTarget = try XCTUnwrap(mappedProject.targets["ForeignBuild_SharedKMP"])
        let script = try XCTUnwrap(aggregateTarget.scripts.first)
        XCTAssertEqual(script.inputPaths, [
            srcFolder.pathString,
            gradleFile.pathString,
            "/Project/SharedKMP/**/*.kt",
        ])
    }

    func test_map_doesNothingWhenNoForeignBuildDependencies() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let target = Target.test(
            name: "App",
            dependencies: [.target(name: "Framework1")]
        )
        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project]
        )

        // When
        let (mappedGraph, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEmpty(sideEffects)
        XCTAssertEqual(mappedGraph.projects[projectPath]?.targets.count, project.targets.count)
    }

    func test_map_handlesFrameworkOutput() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/Lib.framework")
        let target = Target.test(
            name: "App",
            dependencies: [
                .foreignBuild(
                    name: "Lib",
                    script: "make build",
                    output: .framework(path: outputPath, linking: .dynamic),
                    cacheInputs: []
                ),
            ]
        )
        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let mappedProject = try XCTUnwrap(mappedGraph.projects[projectPath])
        let aggregateTarget = try XCTUnwrap(mappedProject.targets["ForeignBuild_Lib"])
        XCTAssertEqual(aggregateTarget.scripts.first?.outputPaths, [outputPath.pathString])
    }

    func test_map_handlesLibraryOutput() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/libRust.a")
        let headersPath = try AbsolutePath(validating: "/Project/headers")
        let target = Target.test(
            name: "App",
            dependencies: [
                .foreignBuild(
                    name: "RustLib",
                    script: "cargo build",
                    output: .library(path: outputPath, publicHeaders: headersPath, swiftModuleMap: nil, linking: .static),
                    cacheInputs: []
                ),
            ]
        )
        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let mappedProject = try XCTUnwrap(mappedGraph.projects[projectPath])
        let aggregateTarget = try XCTUnwrap(mappedProject.targets["ForeignBuild_RustLib"])
        XCTAssertEqual(aggregateTarget.scripts.first?.outputPaths, [outputPath.pathString])
    }

    func test_map_aggregateTargetInheritsDestinationsFromConsumingTarget() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/SharedKMP.xcframework")
        let destinations: Destinations = [.iPhone, .iPad, .macCatalyst]
        let target = Target.test(
            name: "Framework1",
            destinations: destinations,
            dependencies: [
                .foreignBuild(
                    name: "SharedKMP",
                    script: "gradle build",
                    output: .xcframework(path: outputPath, linking: .dynamic),
                    cacheInputs: []
                ),
            ]
        )
        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let mappedProject = try XCTUnwrap(mappedGraph.projects[projectPath])
        let aggregateTarget = try XCTUnwrap(mappedProject.targets["ForeignBuild_SharedKMP"])
        XCTAssertEqual(aggregateTarget.destinations, destinations)
    }

    func test_map_runsScriptWhenOutputDoesNotExist() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/SharedKMP.xcframework")
        let target = Target.test(
            name: "Framework1",
            dependencies: [
                .foreignBuild(
                    name: "SharedKMP",
                    script: "gradle build",
                    output: .xcframework(path: outputPath, linking: .dynamic),
                    cacheInputs: []
                ),
            ]
        )
        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project]
        )

        // When
        _ = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEqual(scriptRunnerCallCount, 1)
        XCTAssertEqual(lastScriptRunnerArgs?.script, "gradle build")
        XCTAssertEqual(lastScriptRunnerArgs?.projectPath, projectPath)
    }

    func test_map_doesNotRunScriptWhenOutputExists() async throws {
        // Given
        let temporaryDir = try temporaryPath()
        let outputPath = temporaryDir.appending(components: "build", "SharedKMP.xcframework")
        try await FileSystem().makeDirectory(at: outputPath)

        let target = Target.test(
            name: "Framework1",
            dependencies: [
                .foreignBuild(
                    name: "SharedKMP",
                    script: "gradle build",
                    output: .xcframework(path: outputPath, linking: .dynamic),
                    cacheInputs: []
                ),
            ]
        )
        let project = Project.test(path: temporaryDir, targets: [target])
        let graph = Graph.test(
            path: temporaryDir,
            projects: [temporaryDir: project]
        )

        // When
        _ = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEqual(scriptRunnerCallCount, 0)
    }
}
