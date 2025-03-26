import Foundation
import MCP
import TuistSupport

// Server references: https://github.com/modelcontextprotocol/servers/tree/main/src
public struct MCPCommandService {
    private let resourcesFactory: MCPResourcesFactorying
    
    public init() {
        self.init(resourcesFactory: MCPResourcesFactory())
    }
    
    init(resourcesFactory: MCPResourcesFactorying) {
        self.resourcesFactory = resourcesFactory
    }

    public func run() async throws {
        let server = Server(
            name: "Tuist",
            version: Constants.version,
            capabilities: .init(
                prompts: .init(),
                resources: .init(
                    subscribe: true
                ),
                tools: .init()
            )
        )
        
        try await server.start(transport: StdioTransport())

        await server.withMethodHandler(ListResources.self) { params in
            return try await resourcesFactory.list()
        }
        
        await server.withMethodHandler(ReadResource.self) { resource in
            
            return .init(contents: [])
        }
        
        try await Task.sleep(nanoseconds: 1_000_000_000_000_000)
    }
}
