import Darwin
import Foundation
import Mockable

@Mockable
protocol MCPServerCommandResolving {
    func resolve() -> (String, [String])
}

struct MCPServerCommandResolver: MCPServerCommandResolving {
    private let executablePath: String

    init(executablePath: String = Self.getExecutablePath()) {
        self.executablePath = executablePath
    }

    func resolve() -> (String, [String]) {
        print(executablePath)
        return (executablePath, ["mcp", "start"])
    }

    private static func getExecutablePath() -> String! {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        var pathLength = UInt32(buffer.count)
        if _NSGetExecutablePath(&buffer, &pathLength) == 0 {
            return String(cString: buffer)
        }
        return nil
    }
}
