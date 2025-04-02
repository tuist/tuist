import Foundation
import Mockable

@Mockable
protocol MCPServerCommandResolving {
    func resolve() -> (String, [String])
}

struct MCPServerCommandResolver: MCPServerCommandResolving {
    private let executablePath: String

    init(executablePath: String = CommandLine.arguments[0]) {
        self.executablePath = executablePath
    }

    func resolve() -> (String, [String]) {
        return (executablePath, ["mcp", "start"])
    }
}
