import DOT
import FileSystem
import FileSystemTesting
import Foundation
import GraphViz
import Mockable
import ProjectAutomation
import Testing
import TuistCore
import TuistGenerator
import TuistLoader
import TuistPlugin
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistKit

struct GraphCommandServiceTests {
    private let manifestGraphLoader = MockManifestGraphLoading()
    private let manifestLoader = MockManifestLoading()
    private let graphVizMapper = MockGraphToGraphVizMapper()
    private let xcodeGraphMapper = MockXcodeGraphMapping()
    private let configLoader = MockConfigLoading()
    private let subject: GraphCommandService

    init() {
        subject = GraphCommandService(
            graphVizGenerator: graphVizMapper,
            manifestGraphLoader: manifestGraphLoader,
            manifestLoader: manifestLoader,
            xcodeGraphMapper: xcodeGraphMapper,
            configLoader: configLoader
        )
    }

    @Test(.inTemporaryDirectory) func run_whenDot_outputsToFile() async throws {
        try await withMockedDependencies {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let fileSystem = FileSystem()
            let graphPath = temporaryDirectory.appending(component: "graph.dot")
            let projectManifestPath = temporaryDirectory.appending(component: "Project.swift")

            given(manifestLoader)
                .hasRootManifest(at: .any)
                .willReturn(true)

            try await fileSystem.touch(graphPath)
            try await fileSystem.touch(projectManifestPath)
            graphVizMapper.stubMap = Graph()

            given(manifestGraphLoader)
                .load(path: .any, disableSandbox: .any)
                .willReturn((.test(), [], MapperEnvironment(), []))

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())

            try await subject.run(
                format: .dot,
                layoutAlgorithm: .dot,
                skipTestTargets: false,
                skipExternalDependencies: false,
                open: false,
                platformToFilter: nil,
                targetsToFilter: [],
                sourceTargets: [],
                sinkTargets: [],
                directOnly: false,
                typeFilter: [],
                outputFields: nil,
                path: temporaryDirectory,
                outputPath: temporaryDirectory,
                stdout: false
            )

            let got = try await fileSystem.readTextFile(at: graphPath)
            #expect(got == "graph { }")
        }
    }

    @Test(.inTemporaryDirectory) func run_whenLegacyJSON_outputsToFile() async throws {
        try await withMockedDependencies {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let fileSystem = FileSystem()
            let graphPath = temporaryDirectory.appending(component: "graph.json")
            let projectManifestPath = temporaryDirectory.appending(component: "Project.swift")

            given(manifestLoader)
                .hasRootManifest(at: .any)
                .willReturn(true)

            try await fileSystem.touch(graphPath)
            try await fileSystem.touch(projectManifestPath)

            given(manifestGraphLoader)
                .load(path: .any, disableSandbox: .any)
                .willReturn((.test(), [], MapperEnvironment(), []))

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())

            try await subject.run(
                format: .legacyJSON,
                layoutAlgorithm: .dot,
                skipTestTargets: false,
                skipExternalDependencies: false,
                open: false,
                platformToFilter: nil,
                targetsToFilter: [],
                sourceTargets: [],
                sinkTargets: [],
                directOnly: false,
                typeFilter: [],
                outputFields: nil,
                path: temporaryDirectory,
                outputPath: temporaryDirectory,
                stdout: false
            )

            let got = try await fileSystem.readTextFile(at: graphPath)
            let result = try JSONDecoder().decode(
                ProjectAutomation.Graph.self,
                from: got.data(using: .utf8)!
            )
            #expect(result == ProjectAutomation.Graph(name: "graph", path: "/", projects: [:]))
        }
    }

    @Test(.inTemporaryDirectory) func run_whenJSON_outputsToFile() async throws {
        try await withMockedDependencies {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let fileSystem = FileSystem()
            let graphPath = temporaryDirectory.appending(component: "graph.json")
            let projectManifestPath = temporaryDirectory.appending(component: "Project.swift")

            try await fileSystem.touch(graphPath)
            try await fileSystem.touch(projectManifestPath)

            given(manifestLoader)
                .hasRootManifest(at: .any)
                .willReturn(true)

            given(manifestGraphLoader)
                .load(path: .any, disableSandbox: .any)
                .willReturn((.test(), [], MapperEnvironment(), []))

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())

            try await subject.run(
                format: .json,
                layoutAlgorithm: .dot,
                skipTestTargets: false,
                skipExternalDependencies: false,
                open: false,
                platformToFilter: nil,
                targetsToFilter: [],
                sourceTargets: [],
                sinkTargets: [],
                directOnly: false,
                typeFilter: [],
                outputFields: nil,
                path: temporaryDirectory,
                outputPath: temporaryDirectory,
                stdout: false
            )

            let got = try await fileSystem.readTextFile(at: graphPath)
            let result = try JSONDecoder().decode(
                XcodeGraph.Graph.self,
                from: got.data(using: .utf8)!
            )
            #expect(result == .test())
        }
    }

    @Test(.inTemporaryDirectory) func run_whenJSON_andHasNoRootManifest_usesXcodeGraphMapper() async throws {
        try await withMockedDependencies {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let fileSystem = FileSystem()
            let graphPath = temporaryDirectory.appending(component: "graph.json")

            try await fileSystem.touch(graphPath)

            given(manifestLoader)
                .hasRootManifest(at: .any)
                .willReturn(false)

            given(xcodeGraphMapper)
                .map(at: .any)
                .willReturn(.test())

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())

            try await subject.run(
                format: .json,
                layoutAlgorithm: .dot,
                skipTestTargets: false,
                skipExternalDependencies: false,
                open: false,
                platformToFilter: nil,
                targetsToFilter: [],
                sourceTargets: [],
                sinkTargets: [],
                directOnly: false,
                typeFilter: [],
                outputFields: nil,
                path: temporaryDirectory,
                outputPath: temporaryDirectory,
                stdout: false
            )

            let got = try await fileSystem.readTextFile(at: graphPath)
            let result = try JSONDecoder().decode(
                XcodeGraph.Graph.self,
                from: got.data(using: .utf8)!
            )
            #expect(result == .test())
        }
    }

    @Test(.inTemporaryDirectory) func run_whenStdout_withPNG_throwsError() async throws {
        try await withMockedDependencies {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

            given(manifestLoader)
                .hasRootManifest(at: .any)
                .willReturn(true)

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())

            await #expect(throws: GraphServiceError.stdoutNotSupportedForFormat(.png)) {
                try await subject.run(
                    format: .png,
                    layoutAlgorithm: .dot,
                    skipTestTargets: false,
                    skipExternalDependencies: false,
                    open: false,
                    platformToFilter: nil,
                    targetsToFilter: [],
                    sourceTargets: [],
                    sinkTargets: [],
                    directOnly: false,
                    typeFilter: [],
                    outputFields: nil,
                    path: temporaryDirectory,
                    outputPath: temporaryDirectory,
                    stdout: true
                )
            }
        }
    }

    @Test(.inTemporaryDirectory) func run_whenStdout_withSVG_throwsError() async throws {
        try await withMockedDependencies {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

            given(manifestLoader)
                .hasRootManifest(at: .any)
                .willReturn(true)

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())

            await #expect(throws: GraphServiceError.stdoutNotSupportedForFormat(.svg)) {
                try await subject.run(
                    format: .svg,
                    layoutAlgorithm: .dot,
                    skipTestTargets: false,
                    skipExternalDependencies: false,
                    open: false,
                    platformToFilter: nil,
                    targetsToFilter: [],
                    sourceTargets: [],
                    sinkTargets: [],
                    directOnly: false,
                    typeFilter: [],
                    outputFields: nil,
                    path: temporaryDirectory,
                    outputPath: temporaryDirectory,
                    stdout: true
                )
            }
        }
    }

    @Test(.inTemporaryDirectory) func run_whenToon_outputsToFile() async throws {
        try await withMockedDependencies {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let fileSystem = FileSystem()
            let graphPath = temporaryDirectory.appending(component: "graph.toon")
            let projectManifestPath = temporaryDirectory.appending(component: "Project.swift")

            try await fileSystem.touch(graphPath)
            try await fileSystem.touch(projectManifestPath)

            given(manifestLoader)
                .hasRootManifest(at: .any)
                .willReturn(true)

            given(manifestGraphLoader)
                .load(path: .any, disableSandbox: .any)
                .willReturn((.test(), [], MapperEnvironment(), []))

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())

            try await subject.run(
                format: .toon,
                layoutAlgorithm: .dot,
                skipTestTargets: false,
                skipExternalDependencies: false,
                open: false,
                platformToFilter: nil,
                targetsToFilter: [],
                sourceTargets: [],
                sinkTargets: [],
                directOnly: false,
                typeFilter: [],
                outputFields: nil,
                path: temporaryDirectory,
                outputPath: temporaryDirectory,
                stdout: false
            )

            let got = try await fileSystem.readTextFile(at: graphPath)
            #expect(got.contains("name:"))
            #expect(got.contains("path:"))
        }
    }

    @Test(.inTemporaryDirectory) func run_whenStdout_withToon_outputsToStdout() async throws {
        try await withMockedDependencies {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let projectManifestPath = temporaryDirectory.appending(component: "Project.swift")
            let fileSystem = FileSystem()

            try await fileSystem.touch(projectManifestPath)

            given(manifestLoader)
                .hasRootManifest(at: .any)
                .willReturn(true)

            given(manifestGraphLoader)
                .load(path: .any, disableSandbox: .any)
                .willReturn((.test(), [], MapperEnvironment(), []))

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())

            try await subject.run(
                format: .toon,
                layoutAlgorithm: .dot,
                skipTestTargets: false,
                skipExternalDependencies: false,
                open: false,
                platformToFilter: nil,
                targetsToFilter: [],
                sourceTargets: [],
                sinkTargets: [],
                directOnly: false,
                typeFilter: [],
                outputFields: nil,
                path: temporaryDirectory,
                outputPath: temporaryDirectory,
                stdout: true
            )
        }
    }
}
