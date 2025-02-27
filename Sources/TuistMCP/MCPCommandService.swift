import Foundation
import JSONSchemaBuilder
import MCPServer
import TuistSupport

@Schemable
struct RepeatToolInput {
    let text: String
}

// Server references: https://github.com/modelcontextprotocol/servers/tree/main/src
public struct MCPCommandService {
    private let resourceFactory: MCPResourceFactorying

    public init() {
        self.init(resourceFactory: MCPResourceFactory())
    }

    init(resourceFactory: MCPResourceFactorying) {
        self.resourceFactory = resourceFactory
    }

    public func run() async throws {
        try await initServer().waitForDisconnection()
    }

    private func initServer() async throws -> MCPServer {
        let implementation = Implementation(name: "tuist", version: Constants.version)
        return try await MCPServer(
            info: implementation,
            capabilities: initCapabilities(),
            transport: .stdio()
        )
    }

    private func initCapabilities() -> ServerCapabilityHandlers {
        ServerCapabilityHandlers(tools: initTools(), resources: initResources())
    }

    private func initTools() -> [any CallableTool] {
        [
            //            Tool(name: "repeat") { (_: RepeatToolInput) in
//                [.text(.init(text: "Repeat"))]
//            },
        ]
    }

    private func initResources() -> ResourcesCapabilityHandler {
        ResourcesCapabilityHandler(readResource: { params -> ReadResourceRequest.Result in
            return .init(contents: [
                .text(.init(uri: params.uri, text: "graph")),
            ])
        }, listResource: { _ -> ListResourcesRequest.Result in
            return .init(resources: try await resourceFactory.fetch())
        }, listResourceTemplates: { _ -> ListResourceTemplatesRequest.Result in
            return .init(resourceTemplates: [])
        })
    }
}
