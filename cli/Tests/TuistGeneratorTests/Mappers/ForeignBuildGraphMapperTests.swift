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

    @Test(.inTemporaryDirectory)
    func map_setsInputPathsFromInputs() async throws {
        // Given
        let fileSystem = FileSystem()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let srcFolder = temporaryDirectory.appending(components: "SharedKMP", "src")
        let subFolder = srcFolder.appending(component: "sub")
        let greetingFile = srcFolder.appending(component: "Greeting.kt")
        let mainFile = subFolder.appending(component: "Main.kt")
        let gradleFile = temporaryDirectory.appending(components: "SharedKMP", "build.gradle.kts")

        try await fileSystem.makeDirectory(at: subFolder)
        try await fileSystem.writeText("", at: greetingFile, options: [.overwrite])
        try await fileSystem.writeText("", at: mainFile, options: [.overwrite])
        try await fileSystem.writeText("", at: gradleFile, options: [.overwrite])

        let outputPath = temporaryDirectory.appending(components: "build", "SharedKMP.xcframework")
        let foreignBuildTarget = Target.test(
            name: "SharedKMP",
            foreignBuild: ForeignBuild(
                script: "gradle build",
                inputs: [
                    .folder(srcFolder),
                    .file(gradleFile),
                    .script("git rev-parse HEAD"),
                ],
                output: .xcframework(path: outputPath, linking: .dynamic)
            )
        )
        let consumingTarget = Target.test(
            name: "Framework1",
            dependencies: [.target(name: "SharedKMP")]
        )
        let project = Project.test(
            path: temporaryDirectory,
            targets: [foreignBuildTarget, consumingTarget]
        )
        let graph = Graph.test(
            path: temporaryDirectory,
            projects: [temporaryDirectory: project]
        )

        // When
        let mapper = ForeignBuildGraphMapper(fileSystem: fileSystem)
        let (mappedGraph, _, _) = try await mapper.map(graph: graph, environment: MapperEnvironment())

        // Then
        let mappedProject = try #require(mappedGraph.projects[temporaryDirectory])
        let mappedForeignTarget = try #require(mappedProject.targets["SharedKMP"])
        let script = try #require(mappedForeignTarget.scripts.first)
        #expect(script.inputPaths.sorted() == [
            greetingFile.pathString,
            mainFile.pathString,
            gradleFile.pathString,
        ].sorted())
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
    func map_returnsNoSideEffects() async throws {
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
        #expect(sideEffects.isEmpty)
    }
}
