import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import XcodeGraph
@testable import TuistCore
@testable import TuistGenerator
@testable import TuistTesting

struct ForeignBuildSideEffectGraphMapperTests {
    private let subject = ForeignBuildSideEffectGraphMapper()

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

    @Test
    func map_doesNotReturnSideEffectWhenForeignBuildTargetNotInGraph() async throws {
        // Given: a graph with no foreign build targets (simulates a pruned/cached target)
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
        let (_, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        #expect(sideEffects.isEmpty)
    }
}
