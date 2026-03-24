import DOT
import FileSystem
import FileSystemTesting
import Foundation
import GraphViz
import Mockable
import ProjectAutomation
import Testing
import TuistConfigLoader
import TuistCore
import TuistLoader
import TuistNooraTesting
import TuistPlugin
import TuistSupport
import TuistTesting
import XcodeGraph
import XcodeProj

@testable import TuistKit

struct GraphServiceTests {
    private var manifestGraphLoader: MockManifestGraphLoading!
    private var manifestLoader: MockManifestLoading!
    private var graphVizMapper: MockGraphToGraphVizMapper!
    private var xcodeGraphMapper: MockXcodeGraphMapping!
    private var configLoader: MockConfigLoading!
    private var subject: GraphService!
    private let fileSystem = FileSystem()

    init() {
        graphVizMapper = MockGraphToGraphVizMapper()
        manifestGraphLoader = MockManifestGraphLoading()
        manifestLoader = MockManifestLoading()
        xcodeGraphMapper = MockXcodeGraphMapping()
        configLoader = MockConfigLoading()

        subject = GraphService(
            graphVizGenerator: graphVizMapper,
            manifestGraphLoader: manifestGraphLoader,
            manifestLoader: manifestLoader,
            xcodeGraphMapper: xcodeGraphMapper,
            configLoader: configLoader
        )
    }

    @Test(.inTemporaryDirectory) func run_whenDot() async throws {
        try await withMockedDependencies {
            // Given
            let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
            let graphPath = temporaryPath.appending(component: "graph.dot")
            let projectManifestPath = temporaryPath.appending(component: "Project.swift")

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

            // When
            try await subject.run(
                format: .dot,
                layoutAlgorithm: .dot,
                skipTestTargets: false,
                skipExternalDependencies: false,
                open: false,
                platformToFilter: nil,
                targetsToFilter: [],
                path: temporaryPath,
                outputPath: temporaryPath
            )
            let got = try await fileSystem.readTextFile(at: graphPath)
            let expected = "graph { }"
            // Then
            #expect(got == expected)
        }
    }

    @Test(.inTemporaryDirectory) func run_when_legacyJSON() async throws {
        try await withMockedDependencies {
            // Given
            let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
            let graphPath = temporaryPath.appending(component: "graph.json")
            let projectManifestPath = temporaryPath.appending(component: "Project.swift")

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

            // When
            try await subject.run(
                format: .legacyJSON,
                layoutAlgorithm: .dot,
                skipTestTargets: false,
                skipExternalDependencies: false,
                open: false,
                platformToFilter: nil,
                targetsToFilter: [],
                path: temporaryPath,
                outputPath: temporaryPath
            )
            let got = try await fileSystem.readTextFile(at: graphPath)

            let result = try JSONDecoder().decode(
                ProjectAutomation.Graph.self, from: got.data(using: .utf8)!
            )
            // Then
            #expect(result == ProjectAutomation.Graph(name: "graph", path: "/", projects: [:]))
        }
    }

    @Test(.inTemporaryDirectory) func run_when_json() async throws {
        try await withMockedDependencies {
            // Given
            let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
            let graphPath = temporaryPath.appending(component: "graph.json")
            let projectManifestPath = temporaryPath.appending(component: "Project.swift")

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

            // When
            try await subject.run(
                format: .json,
                layoutAlgorithm: .dot,
                skipTestTargets: false,
                skipExternalDependencies: false,
                open: false,
                platformToFilter: nil,
                targetsToFilter: [],
                path: temporaryPath,
                outputPath: temporaryPath
            )
            let got = try await fileSystem.readTextFile(at: graphPath)

            let result = try JSONDecoder().decode(
                XcodeGraph.Graph.self, from: got.data(using: .utf8)!
            )
            // Then
            #expect(result == .test())
        }
    }

    @Test(.inTemporaryDirectory) func run_when_json_and_has_no_root_manifest() async throws {
        try await withMockedDependencies {
            // Given
            let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
            let graphPath = temporaryPath.appending(component: "graph.json")

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

            // When
            try await subject.run(
                format: .json,
                layoutAlgorithm: .dot,
                skipTestTargets: false,
                skipExternalDependencies: false,
                open: false,
                platformToFilter: nil,
                targetsToFilter: [],
                path: temporaryPath,
                outputPath: temporaryPath
            )
            let got = try await fileSystem.readTextFile(at: graphPath)

            let result = try JSONDecoder().decode(
                XcodeGraph.Graph.self, from: got.data(using: .utf8)!
            )

            // Then
            #expect(result == .test())

            #expect(
                ui() ==
                    """
                    ✔ Success
                      Graph exported to \(graphPath.pathString)
                    """
            )
        }
    }
}
