import Darwin
import Foundation
import Mockable
import TuistSupport

@Mockable
protocol MCPServerCommandResolving {
    func resolve() -> (String, [String])
}

struct MCPServerCommandResolver: MCPServerCommandResolving {
    private let executablePath: String

    init(executablePath: String = Environment.current.currentExecutablePath()?.pathString ?? "tuist") {
        self.executablePath = executablePath
    }

    func resolve() -> (String, [String]) {
        return (executablePath, ["mcp", "start"])
    }
}
