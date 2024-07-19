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
        // swiftformat:disable all
        let isCommandMachineReadable = CommandLine.arguments.count > 1 && machineReadableCommands.map { $0._commandName }.contains(CommandLine.arguments[1])
        // swiftformat:enable all
        if isCommandMachineReadable || CommandLine.arguments.contains("--json") {
            TuistSupport.LogOutput.bootstrap(
                config: LoggingConfig(
                    loggerType: .json,
                    verbose: ProcessEnv.vars[Constants.EnvironmentVariables.verbose] != nil
                )
            )
        } else {
            TuistSupport.LogOutput.bootstrap()
        }

        try TuistSupport.Environment.shared.bootstrap()

        try await TuistCommand.main()
    }
}
