import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import XcodeGraph
@testable import TuistCore
@testable import TuistGenerator
@testable import TuistTesting

struct ForeignBuildGraphMapperTests {
    private let subject = ForeignBuildGraphMapper()

    @Test
    func map_configuresForeignBuildTargetWithScriptPhase() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/SharedKMP.xcframework")
        let foreignBuildTarget = Target.test(
            name: "SharedKMP",
            foreignBuild: ForeignBuild(
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
        let mappedProject = try #require(mappedGraph.projects[projectPath])
        let mappedForeignTarget = try #require(mappedProject.targets["SharedKMP"])

        #expect(mappedForeignTarget.metadata.tags.contains("tuist:foreign-build-aggregate"))
        #expect(mappedForeignTarget.scripts.count == 1)
        #expect(mappedForeignTarget.scripts.first?.name == "Foreign Build: SharedKMP")
        #expect(mappedForeignTarget.scripts.first?.script == .embedded("gradle build"))
        #expect(mappedForeignTarget.scripts.first?.outputPaths == [outputPath.pathString])
    }

    @Test
    func map_addsForeignBuildOutputDependencyForConsumingTarget() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/SharedKMP.xcframework")
        let foreignBuildTarget = Target.test(
            name: "SharedKMP",
            foreignBuild: ForeignBuild(
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
        #expect(mappedGraph.dependencies[consumingDep]?.contains(expectedOutputDep) == true)

        let foreignBuildDep = GraphDependency.target(name: "SharedKMP", path: projectPath)
        #expect(mappedGraph.dependencies[foreignBuildDep] == Set())
    }

    @Test
    func map_multipleConsumersShareSameForeignBuildTarget() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/SharedKMP.xcframework")
        let foreignBuildTarget = Target.test(
            name: "SharedKMP",
            foreignBuild: ForeignBuild(
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
        #expect(mappedGraph.dependencies[dep1]?.contains(expectedOutputDep) == true)
        #expect(mappedGraph.dependencies[dep2]?.contains(expectedOutputDep) == true)
    }

    @Test
    func map_setsInputPathsFromInputs() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/SharedKMP.xcframework")
        let srcFolder = try AbsolutePath(validating: "/Project/SharedKMP/src")
        let gradleFile = try AbsolutePath(validating: "/Project/SharedKMP/build.gradle.kts")
        let ktFile = try AbsolutePath(validating: "/Project/SharedKMP/src/Main.kt")
        let foreignBuildTarget = Target.test(
            name: "SharedKMP",
            foreignBuild: ForeignBuild(
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
        let mappedProject = try #require(mappedGraph.projects[projectPath])
        let mappedForeignTarget = try #require(mappedProject.targets["SharedKMP"])
        let script = try #require(mappedForeignTarget.scripts.first)
        #expect(script.inputPaths == [
            srcFolder.pathString,
            gradleFile.pathString,
            ktFile.pathString,
        ])
    }

    @Test
    func map_doesNothingWhenNoForeignBuildTargets() async throws {
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
        #expect(sideEffects.isEmpty)
        #expect(mappedGraph.projects[projectPath]?.targets.count == project.targets.count)
    }

    @Test
    func map_handlesFrameworkOutput() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/Lib.framework")
        let foreignBuildTarget = Target.test(
            name: "Lib",
            foreignBuild: ForeignBuild(
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
        let mappedProject = try #require(mappedGraph.projects[projectPath])
        let mappedForeignTarget = try #require(mappedProject.targets["Lib"])
        #expect(mappedForeignTarget.scripts.first?.outputPaths == [outputPath.pathString])
    }

    @Test
    func map_returnsSideEffectWhenOutputDoesNotExist() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let outputPath = try AbsolutePath(validating: "/Project/build/SharedKMP.xcframework")
        let foreignBuildTarget = Target.test(
            name: "SharedKMP",
            foreignBuild: ForeignBuild(
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
        #expect(sideEffects.count == 1)
        guard case let .command(commandDescriptor) = sideEffects.first else {
            Issue.record("Expected a command side effect")
            return
        }
        #expect(commandDescriptor.command.first == "/bin/sh")
        #expect(commandDescriptor.command.last?.contains("gradle build") == true)
        #expect(commandDescriptor.command.last?.contains("SRCROOT=/Project") == true)
    }

    @Test(.inTemporaryDirectory)
    func map_doesNotReturnSideEffectWhenOutputExists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let outputPath = temporaryDirectory.appending(components: "build", "SharedKMP.xcframework")
        try await FileSystem().makeDirectory(at: outputPath)

        let foreignBuildTarget = Target.test(
            name: "SharedKMP",
            foreignBuild: ForeignBuild(
                script: "gradle build",
                inputs: [],
                output: .xcframework(path: outputPath, linking: .dynamic)
            )
        )
        let consumingTarget = Target.test(
            name: "Framework1",
            dependencies: [.target(name: "SharedKMP")]
        )
        let project = Project.test(path: temporaryDirectory, targets: [foreignBuildTarget, consumingTarget])
        let graph = Graph.test(
            path: temporaryDirectory,
            projects: [temporaryDirectory: project]
        )

        // When
        let (_, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        #expect(sideEffects.isEmpty)
    }
}
