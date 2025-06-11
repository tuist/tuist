import Foundation
import MCP
import TuistSupport

// Server references: https://github.com/modelcontextprotocol/servers/tree/main/src

public struct MCPCommandService {
    private let resourcesRepository: MCPResourcesRepositorying

    public init() {
        self.init(resourcesRepository: MCPResourcesRepository())
    }

    init(resourcesRepository: MCPResourcesRepositorying) {
        self.resourcesRepository = resourcesRepository
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

        await server.withMethodHandler(ListResources.self) { _ in
            return try await resourcesRepository.list()
        }

        await server.withMethodHandler(ListResourceTemplates.self) { _ in
            return try await resourcesRepository.listTemplates()
        }

        await server.withMethodHandler(ReadResource.self) { resource in
            return try await resourcesRepository.read(resource)
        }

        try await Task.sleep(nanoseconds: 1_000_000_000_000_000)
    }
}
