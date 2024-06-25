import Foundation
import Path
import TSCBasic
import TuistKit
import TuistLoader
import TuistSupport

@main
@_documentation(visibility: private)
private enum TuistServer {
    static func main() async throws {
        if CommandLine.arguments.contains("--verbose") {
            try? ProcessEnv.setVar(Constants.EnvironmentVariables.verbose, value: "true")
        }

        let machineReadableCommands = [DumpCommand.self]
        if (CommandLine.arguments.count > 1 && machineReadableCommands.map(\._commandName).contains(CommandLine.arguments[1])) ||
            CommandLine.arguments.contains("--json")
        {
            TuistSupport.LogOutput.bootstrap(config: LoggingConfig(loggerType: .json, verbose: false))
        } else {
            TuistSupport.LogOutput.bootstrap()
        }

        try TuistSupport.Environment.shared.bootstrap()

        try await TuistCommand.main()
    }
}
