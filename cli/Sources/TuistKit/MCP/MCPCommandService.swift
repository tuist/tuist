import Foundation
import MCP
import TuistSupport

// Server references: https://github.com/modelcontextprotocol/servers/tree/main/src

public struct MCPCommandService {
    private let resourcesRepository: MCPResourcesRepositorying
    private let toolsRepository: MCPToolsRepositorying

    public init() {
        let resourcesRepository = MCPResourcesRepository()
        self.init(
            resourcesRepository: resourcesRepository,
            toolsRepository: MCPToolsRepository(resourcesRepository: resourcesRepository)
        )
    }

    init(resourcesRepository: MCPResourcesRepositorying, toolsRepository: MCPToolsRepositorying) {
        self.resourcesRepository = resourcesRepository
        self.toolsRepository = toolsRepository
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

        await server.withMethodHandler(ListPrompts.self) { _ in
            return .init(prompts: [])
        }

        await server.withMethodHandler(ListResources.self) { _ in
            return try await resourcesRepository.list()
        }

        await server.withMethodHandler(ListResourceTemplates.self) { _ in
            return try await resourcesRepository.listTemplates()
        }

        await server.withMethodHandler(ReadResource.self) { resource in
            return try await resourcesRepository.read(resource)
        }

        await server.withMethodHandler(ResourceSubscribe.self) { _ in
            return .init()
        }

        await server.withMethodHandler(ListTools.self) { _ in
            return try await toolsRepository.list()
        }

        await server.withMethodHandler(CallTool.self) { tool in
            return try await toolsRepository.call(tool)
        }

        try await server.start(transport: StdioTransport())

        try await Task.sleep(nanoseconds: 1_000_000_000_000_000)
    }
}
