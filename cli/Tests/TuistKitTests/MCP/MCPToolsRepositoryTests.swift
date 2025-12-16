import Foundation
import MCP
import SwiftyJSON
import Testing

@testable import TuistKit

private actor ResourcesRepositorySpy: MCPResourcesRepositorying {
    let resources: [Resource]
    let readResult: ReadResource.Result
    private(set) var lastReadURI: String?

    init(resources: [Resource], readResult: ReadResource.Result) {
        self.resources = resources
        self.readResult = readResult
    }

    func list() async throws -> ListResources.Result {
        .init(resources: resources)
    }

    func listTemplates() async throws -> ListResourceTemplates.Result {
        .init(templates: [])
    }

    func read(_ resource: ReadResource.Parameters) async throws -> ReadResource.Result {
        lastReadURI = resource.uri
        return readResult
    }
}

struct MCPToolsRepositoryTests {
    @Test func list_includesTuistTools() async throws {
        // Given
        let spy = ResourcesRepositorySpy(resources: [], readResult: .init(contents: []))
        let subject = MCPToolsRepository(resourcesRepository: spy)

        // When
        let got = try await subject.list()

        // Then
        let names = got.tools.map(\.name)
        #expect(names.contains("tuist_list_recent_projects"))
        #expect(names.contains("tuist_read_graph"))
    }

    @Test func call_listRecentProjects_returnsResourcesAsJSON() async throws {
        // Given
        let resources = [
            Resource(name: "Project graph", uri: "tuist:///tmp/project", description: nil, mimeType: "application/json"),
        ]
        let spy = ResourcesRepositorySpy(resources: resources, readResult: .init(contents: []))
        let subject = MCPToolsRepository(resourcesRepository: spy)

        // When
        let got = try await subject.call(.init(name: "tuist_list_recent_projects"))

        // Then
        let content = try #require(got.content.first)
        guard case let .text(text) = content else {
            Issue.record("Expected text content")
            return
        }
        let json = JSON(parseJSON: text)
        #expect(json[0]["name"].stringValue == "Project graph")
        #expect(json[0]["uri"].stringValue == "tuist:///tmp/project")
    }

    @Test func call_readGraph_resolvesDirectoryPathToTuistURI() async throws {
        // Given
        let graph = #"{"graph":"ok"}"#
        let spy = ResourcesRepositorySpy(
            resources: [],
            readResult: .init(contents: [.text(graph, uri: "tuist:///tmp/project", mimeType: "application/json")])
        )
        let subject = MCPToolsRepository(resourcesRepository: spy)

        // When
        _ = try await subject.call(.init(name: "tuist_read_graph", arguments: ["path": "/tmp/project"]))

        // Then
        let lastReadURI = await spy.lastReadURI
        #expect(lastReadURI == "tuist:///tmp/project")
    }

    @Test func call_readGraph_resolvesXcodeprojPathToFileURI() async throws {
        // Given
        let spy = ResourcesRepositorySpy(resources: [], readResult: .init(contents: []))
        let subject = MCPToolsRepository(resourcesRepository: spy)

        // When
        _ = try await subject.call(.init(name: "tuist_read_graph", arguments: ["path": "/tmp/App.xcodeproj"]))

        // Then
        let lastReadURI = await spy.lastReadURI
        #expect(lastReadURI == "file:///tmp/App.xcodeproj")
    }
}
