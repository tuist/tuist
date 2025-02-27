import Foundation
import MCPServer
import TuistSupport

public struct MCPCommandService {
    public init() {}

    public func run() async throws {
        let implementation = Implementation(name: "tuist", version: Constants.version)
        let capabilities = ServerCapabilityHandlers()
        let server = try await MCPServer(
            info: implementation,
            capabilities: capabilities,
            transport: .stdio()
        )
        try await server.waitForDisconnection()
    }
}
