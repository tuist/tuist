import FileSystem
import Foundation
import MCP
import Mockable
import SwiftyJSON
import Testing
import TuistCore
import TuistLoader
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistKit

struct MCPResourcesRepositoryTests {
    private let fileSystem = FileSystem()
    private let manifestGraphLoader = MockManifestGraphLoading()
    private let manifestLoader = MockManifestLoading()
    private let xcodeGraphMapper = MockXcodeGraphMapping()
    private let subject: MCPResourcesRepository
    private let configLoader = MockConfigLoading()

    init() {
        subject = MCPResourcesRepository(
            fileSystem: fileSystem,
            manifestGraphLoader: manifestGraphLoader,
            manifestLoader: manifestLoader,
            xcodeGraphMapper: xcodeGraphMapper,
            configLoader: configLoader
        )
    }

    @Test(.withMockedDependencies(), .inTemporaryDirectory) func list() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let recentPathsStoreMock = try #require(RecentPathsStore.mocked)
        given(recentPathsStoreMock).read().willReturn([temporaryDirectory: RecentPathMetadata(lastUpdated: Date())])

        // When
        let got = try await subject.list()

        // Then
        #expect(got == .init(resources: [Resource(
            name: "\(temporaryDirectory.basename) graph",
            uri: "tuist://\(temporaryDirectory.pathString)",
            description: "A graph representing the project \(temporaryDirectory.basename)",
            mimeType: "application/json"
        )]))
    }

    @Test(.withMockedDependencies()) func listTemplates() async throws {
        // When
        let got = try await subject.listTemplates()

        // Then
        #expect(got == .init(templates: [
            Resource.Template(
                uriTemplate: "file:///{path}",
                name: "An Xcode project or workspace",
                description: "Through this template users can read the graph of an Xcode project or workspace to ask questions about it. They need to pass the absolute path to the Xcode project or workspace."
            ),
        ]))
    }

    @Test(.withMockedDependencies(), .inTemporaryDirectory) func read_when_tuistProject() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let recentPathsStoreMock = try #require(RecentPathsStore.mocked)
        given(recentPathsStoreMock).read().willReturn([temporaryDirectory: RecentPathMetadata(lastUpdated: Date())])
        let graph = XcodeGraph.Graph.test(projects: [temporaryDirectory: .test(targets: [
            .test(name: "Test"),
        ])])
        given(configLoader).loadConfig(path: .value(temporaryDirectory))
            .willReturn(Tuist.test(project: .testGeneratedProject()))
        given(manifestLoader).hasRootManifest(at: .value(temporaryDirectory)).willReturn(true)
        given(manifestGraphLoader).load(path: .value(temporaryDirectory), disableSandbox: .any).willReturn((
            graph,
            [],
            .init(),
            []
        ))

        // When
        let got = try await subject.read(.init(uri: "tuist://\(temporaryDirectory.pathString)"))

        // Then
        let jsonGraph = JSON(parseJSON: try #require(got.contents.first?.text))
        #expect(jsonGraph["projects"][temporaryDirectory.pathString]["targets"][0]["sourcesCount"].intValue == 0)
        #expect(jsonGraph["projects"][temporaryDirectory.pathString]["targets"][0]["resources"].null != nil)
        #expect(jsonGraph["projects"][temporaryDirectory.pathString]["targets"][0]["resourcesCount"].intValue == 0)
        #expect(jsonGraph["projects"][temporaryDirectory.pathString]["targets"][0]["resources"].null != nil)
    }
}
