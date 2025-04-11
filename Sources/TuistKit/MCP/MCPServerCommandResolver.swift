import Darwin
import Foundation
import Mockable
import ServiceContextModule
import TuistSupport

@Mockable
protocol MCPServerCommandResolving {
    func resolve() -> (String, [String])
}

struct MCPServerCommandResolver: MCPServerCommandResolving {

    func resolve() -> (String, [String]) {
        let executablePath = ServiceContext.current!.environment!.currentExecutablePath()?.pathString ?? "tuist"
        return (executablePath, ["mcp", "start"])
    }
}
