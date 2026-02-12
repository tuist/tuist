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

    override func setUp() {
        super.setUp()
        subject = ForeignBuildGraphMapper()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_map_configuresForeignBuildTargetWithScriptPhase() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/SharedKMP.xcframework")
        let foreignBuildTarget = Target.test(
            name: "SharedKMP",
            foreignBuild: ForeignBuildInfo(
                script: "gradle build",
                inputs: [],
                output: .xcframework(path: outputPath, linking: .dynamic)
            )
        )
        let consumingTarget = Target.test(
            name: "Framework1",
            dependencies: [.target(name: "SharedKMP")]
        )
        let project = Project.test(path: projectPath, targets: [foreignBuildTarget, consumingTarget])
        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let mappedProject = try XCTUnwrap(mappedGraph.projects[projectPath])
        let mappedForeignTarget = try XCTUnwrap(mappedProject.targets["SharedKMP"])

        XCTAssertTrue(mappedForeignTarget.metadata.tags.contains("tuist:foreign-build-aggregate"))
        XCTAssertEqual(mappedForeignTarget.scripts.count, 1)
        XCTAssertEqual(mappedForeignTarget.scripts.first?.name, "Foreign Build: SharedKMP")
        XCTAssertEqual(mappedForeignTarget.scripts.first?.script, .embedded("gradle build"))
        XCTAssertEqual(mappedForeignTarget.scripts.first?.outputPaths, [outputPath.pathString])
    }

    func test_map_addsForeignBuildOutputDependencyForConsumingTarget() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/SharedKMP.xcframework")
        let foreignBuildTarget = Target.test(
            name: "SharedKMP",
            foreignBuild: ForeignBuildInfo(
                script: "gradle build",
                inputs: [],
                output: .xcframework(path: outputPath, linking: .dynamic)
            )
        )
        let consumingTarget = Target.test(
            name: "Framework1",
            dependencies: [.target(name: "SharedKMP")]
        )
        let project = Project.test(path: projectPath, targets: [foreignBuildTarget, consumingTarget])
        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project],
            dependencies: [
                .target(name: "Framework1", path: projectPath): Set([.target(name: "SharedKMP", path: projectPath)]),
            ]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let consumingDep = GraphDependency.target(name: "Framework1", path: projectPath)
        let expectedOutputDep = GraphDependency.foreignBuildOutput(
            GraphDependency.ForeignBuildOutput(name: "SharedKMP", path: outputPath, linking: .dynamic)
        )
        XCTAssertTrue(mappedGraph.dependencies[consumingDep]?.contains(expectedOutputDep) == true)

        let foreignBuildDep = GraphDependency.target(name: "SharedKMP", path: projectPath)
        XCTAssertEqual(mappedGraph.dependencies[foreignBuildDep], Set())
    }

    func test_map_multipleConsumersShareSameForeignBuildTarget() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/SharedKMP.xcframework")
        let foreignBuildTarget = Target.test(
            name: "SharedKMP",
            foreignBuild: ForeignBuildInfo(
                script: "gradle build",
                inputs: [],
                output: .xcframework(path: outputPath, linking: .dynamic)
            )
        )
        let consumer1 = Target.test(
            name: "Framework1",
            dependencies: [.target(name: "SharedKMP")]
        )
        let consumer2 = Target.test(
            name: "Framework2",
            dependencies: [.target(name: "SharedKMP")]
        )
        let project = Project.test(path: projectPath, targets: [foreignBuildTarget, consumer1, consumer2])
        let foreignBuildDep = GraphDependency.target(name: "SharedKMP", path: projectPath)
        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project],
            dependencies: [
                .target(name: "Framework1", path: projectPath): Set([foreignBuildDep]),
                .target(name: "Framework2", path: projectPath): Set([foreignBuildDep]),
            ]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let expectedOutputDep = GraphDependency.foreignBuildOutput(
            GraphDependency.ForeignBuildOutput(name: "SharedKMP", path: outputPath, linking: .dynamic)
        )
        let dep1 = GraphDependency.target(name: "Framework1", path: projectPath)
        let dep2 = GraphDependency.target(name: "Framework2", path: projectPath)
        XCTAssertTrue(mappedGraph.dependencies[dep1]?.contains(expectedOutputDep) == true)
        XCTAssertTrue(mappedGraph.dependencies[dep2]?.contains(expectedOutputDep) == true)
    }

    func test_map_setsInputPathsFromInputs() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/SharedKMP.xcframework")
        let srcFolder = try AbsolutePath(validating: "/Project/SharedKMP/src")
        let gradleFile = try AbsolutePath(validating: "/Project/SharedKMP/build.gradle.kts")
        let ktFile = try AbsolutePath(validating: "/Project/SharedKMP/src/Main.kt")
        let foreignBuildTarget = Target.test(
            name: "SharedKMP",
            foreignBuild: ForeignBuildInfo(
                script: "gradle build",
                inputs: [
                    .folder(srcFolder),
                    .file(gradleFile),
                    .file(ktFile),
                    .script("git rev-parse HEAD"),
                ],
                output: .xcframework(path: outputPath, linking: .dynamic)
            )
        )
        let consumingTarget = Target.test(
            name: "Framework1",
            dependencies: [.target(name: "SharedKMP")]
        )
        let project = Project.test(path: projectPath, targets: [foreignBuildTarget, consumingTarget])
        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let mappedProject = try XCTUnwrap(mappedGraph.projects[projectPath])
        let mappedForeignTarget = try XCTUnwrap(mappedProject.targets["SharedKMP"])
        let script = try XCTUnwrap(mappedForeignTarget.scripts.first)
        XCTAssertEqual(script.inputPaths, [
            srcFolder.pathString,
            gradleFile.pathString,
            ktFile.pathString,
        ])
    }

    func test_map_doesNothingWhenNoForeignBuildTargets() async throws {
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
        let foreignBuildTarget = Target.test(
            name: "Lib",
            foreignBuild: ForeignBuildInfo(
                script: "make build",
                inputs: [],
                output: .framework(path: outputPath, linking: .dynamic)
            )
        )
        let consumingTarget = Target.test(
            name: "App",
            dependencies: [.target(name: "Lib")]
        )
        let project = Project.test(path: projectPath, targets: [foreignBuildTarget, consumingTarget])
        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let mappedProject = try XCTUnwrap(mappedGraph.projects[projectPath])
        let mappedForeignTarget = try XCTUnwrap(mappedProject.targets["Lib"])
        XCTAssertEqual(mappedForeignTarget.scripts.first?.outputPaths, [outputPath.pathString])
    }

    func test_map_handlesLibraryOutput() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/libRust.a")
        let headersPath = try AbsolutePath(validating: "/Project/headers")
        let foreignBuildTarget = Target.test(
            name: "RustLib",
            foreignBuild: ForeignBuildInfo(
                script: "cargo build",
                inputs: [],
                output: .library(path: outputPath, publicHeaders: headersPath, swiftModuleMap: nil, linking: .static)
            )
        )
        let consumingTarget = Target.test(
            name: "App",
            dependencies: [.target(name: "RustLib")]
        )
        let project = Project.test(path: projectPath, targets: [foreignBuildTarget, consumingTarget])
        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project]
        )

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let mappedProject = try XCTUnwrap(mappedGraph.projects[projectPath])
        let mappedForeignTarget = try XCTUnwrap(mappedProject.targets["RustLib"])
        XCTAssertEqual(mappedForeignTarget.scripts.first?.outputPaths, [outputPath.pathString])
    }

    func test_map_returnsSideEffectWhenOutputDoesNotExist() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/SharedKMP.xcframework")
        let foreignBuildTarget = Target.test(
            name: "SharedKMP",
            foreignBuild: ForeignBuildInfo(
                script: "gradle build",
                inputs: [],
                output: .xcframework(path: outputPath, linking: .dynamic)
            )
        )
        let consumingTarget = Target.test(
            name: "Framework1",
            dependencies: [.target(name: "SharedKMP")]
        )
        let project = Project.test(path: projectPath, targets: [foreignBuildTarget, consumingTarget])
        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: project]
        )

        // When
        let (_, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEqual(sideEffects.count, 1)
        guard case let .command(commandDescriptor) = sideEffects.first else {
            XCTFail("Expected a command side effect")
            return
        }
        XCTAssertEqual(commandDescriptor.command.first, "/bin/sh")
        XCTAssertTrue(commandDescriptor.command.last?.contains("gradle build") == true)
        XCTAssertTrue(commandDescriptor.command.last?.contains("SRCROOT=/Project") == true)
    }

    func test_map_doesNotReturnSideEffectWhenOutputExists() async throws {
        // Given
        let temporaryDir = try temporaryPath()
        let outputPath = temporaryDir.appending(components: "build", "SharedKMP.xcframework")
        try await FileSystem().makeDirectory(at: outputPath)

        let foreignBuildTarget = Target.test(
            name: "SharedKMP",
            foreignBuild: ForeignBuildInfo(
                script: "gradle build",
                inputs: [],
                output: .xcframework(path: outputPath, linking: .dynamic)
            )
        )
        let consumingTarget = Target.test(
            name: "Framework1",
            dependencies: [.target(name: "SharedKMP")]
        )
        let project = Project.test(path: temporaryDir, targets: [foreignBuildTarget, consumingTarget])
        let graph = Graph.test(
            path: temporaryDir,
            projects: [temporaryDir: project]
        )

        // When
        let (_, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        XCTAssertEmpty(sideEffects)
    }
}
