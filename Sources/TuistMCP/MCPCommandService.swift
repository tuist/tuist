import Foundation
import JSONSchemaBuilder
import MCPServer
import TuistSupport

@Schemable
struct RepeatToolInput {
    let text: String
}

public struct MCPCommandService {
    public init() {}

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
            Tool(name: "repeat") { (_: RepeatToolInput) in
                [.text(.init(text: "Repeat"))]
            },
        ]
    }

    private func initResources() -> ResourcesCapabilityHandler {
        ResourcesCapabilityHandler(readResource: { _ -> ReadResourceRequest.Result in
            return .init(contents: [])
        }, listResource: { _ -> ListResourcesRequest.Result in
            return .init(resources: [])
        }, listResourceTemplates: { _ -> ListResourceTemplatesRequest.Result in
            return .init(resourceTemplates: [])
        })
    }
}
