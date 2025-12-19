import Foundation
import MCP

protocol MCPToolsRepositorying {
    func list() async throws -> ListTools.Result
    func call(_ tool: CallTool.Parameters) async throws -> CallTool.Result
}

struct MCPToolsRepository: MCPToolsRepositorying {
    private let resourcesRepository: MCPResourcesRepositorying
    private let jsonEncoder = JSONEncoder()

    init(resourcesRepository: MCPResourcesRepositorying = MCPResourcesRepository()) {
        self.resourcesRepository = resourcesRepository
    }

    func list() async throws -> ListTools.Result {
        return .init(tools: [
            Self.listRecentProjectsTool,
            Self.readGraphTool,
        ])
    }

    func call(_ tool: CallTool.Parameters) async throws -> CallTool.Result {
        switch tool.name {
        case Self.listRecentProjectsTool.name:
            let resources = try await resourcesRepository.list().resources
            let content = String(data: try jsonEncoder.encode(resources), encoding: .utf8) ?? "[]"
            return .init(content: [.text(content)])
        case Self.readGraphTool.name:
            guard let uri = Self.resolveURI(from: tool.arguments) else {
                return .init(
                    content: [
                        .text(#"Missing "path" (absolute path) or "uri"."#),
                    ],
                    isError: true
                )
            }

            let resource = ReadResource.Parameters(uri: uri)
            let result = try await resourcesRepository.read(resource)
            let content = result.contents.compactMap { $0.text }.joined(separator: "\n")
            if content.isEmpty {
                return .init(content: [.text("No graph found for \(uri).")], isError: true)
            } else {
                return .init(content: [.text(content)])
            }
        default:
            return .init(content: [.text("Unknown tool: \(tool.name)")], isError: true)
        }
    }

    private static func resolveURI(from arguments: [String: Value]?) -> String? {
        if let uri = arguments?["uri"]?.stringValue, !uri.isEmpty {
            return uri
        }

        if let path = arguments?["path"]?.stringValue, !path.isEmpty {
            if path.hasPrefix("tuist://") || path.hasPrefix("file://") {
                return path
            } else if path.hasSuffix(".xcodeproj") || path.hasSuffix(".xcworkspace") {
                return "file://\(path)"
            } else {
                return "tuist://\(path)"
            }
        }

        return nil
    }

    private static let listRecentProjectsTool = Tool(
        name: "tuist_list_recent_projects",
        description: "Lists recently accessed Xcode projects/workspaces that Tuist can expose as graphs.",
        inputSchema: [
            "type": "object",
            "properties": [:],
        ],
        annotations: .init(
            title: "List recent projects",
            readOnlyHint: true,
            openWorldHint: false
        )
    )

    private static let readGraphTool = Tool(
        name: "tuist_read_graph",
        description: "Returns the dependency graph for a Tuist/Xcode project as JSON.",
        inputSchema: [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "Absolute path to a Tuist project directory, .xcodeproj, or .xcworkspace.",
                ],
                "uri": [
                    "type": "string",
                    "description": "Optional MCP resource URI (tuist://... or file://...). Takes precedence over path.",
                ],
            ],
        ],
        annotations: .init(
            title: "Read project graph",
            readOnlyHint: true,
            openWorldHint: false
        )
    )
}
