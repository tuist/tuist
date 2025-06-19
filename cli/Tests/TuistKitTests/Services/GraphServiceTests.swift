import DOT
import Foundation
import GraphViz
import Mockable
import ProjectAutomation
import TuistCore
import TuistLoader
import TuistPlugin
import TuistSupport
import TuistTesting
import XcodeGraph
import XcodeProj
import XCTest

@testable import TuistKit

final class GraphServiceTests: TuistUnitTestCase {
    private var manifestGraphLoader: MockManifestGraphLoading!
    private var manifestLoader: MockManifestLoading!
    private var graphVizMapper: MockGraphToGraphVizMapper!
    private var xcodeGraphMapper: MockXcodeGraphMapping!
    private var configLoader: MockConfigLoading!
    private var subject: GraphService!

    override func setUp() {
        super.setUp()
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

    override func tearDown() {
        graphVizMapper = nil
        manifestGraphLoader = nil
        manifestLoader = nil
        xcodeGraphMapper = nil
        subject = nil
        super.tearDown()
    }

    func test_run_whenDot() async throws {
        try await withMockedDependencies {
            // Given
            let temporaryPath = try temporaryPath()
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
            XCTAssertEqual(got, expected)
        }
    }

    func test_run_when_legacyJSON() async throws {
        try await withMockedDependencies {
            // Given
            let temporaryPath = try temporaryPath()
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
            XCTAssertEqual(result, ProjectAutomation.Graph(name: "graph", path: "/", projects: [:]))
        }
    }

    func test_run_when_json() async throws {
        try await withMockedDependencies {
            // Given
            let temporaryPath = try temporaryPath()
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
            XCTAssertEqual(result, .test())
        }
    }

    func test_run_when_json_and_has_no_root_manifest() async throws {
        try await withMockedDependencies {
            // Given
            let temporaryPath = try temporaryPath()
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
            XCTAssertEqual(result, .test())

            XCTAssertEqual(
                ui(),
                """
                ✔ Success
                  Graph exported to \(graphPath.pathString)
                """
            )
        }
    }
}
